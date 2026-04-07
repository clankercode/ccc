# Elixir Implementation Plan

## 1. Mix Project Structure

```
elixir/
├── mix.exs
├── .formatter.exs
├── lib/
│   └── ccc/
│       ├── command_spec.ex
│       ├── completed_run.ex
│       ├── runner.ex
│       ├── prompt_spec.ex
│       └── cli.ex
├── escript/
│   └── ccc.ex            # escript entrypoint (mix escript.build → ./ccc)
├── test/
│   ├── test_helper.exs
│   ├── ccc/
│   │   ├── prompt_spec_test.exs
│   │   ├── runner_test.exs
│   │   └── cli_test.exs
│   └── ccc_test.exs      # integration via escript invocation
├── README.md
└── PLAN.md
```

**`mix.exs`** — standard Mix project, no deps. Define an `escript` entry:

```elixir
def project do
  [
    app: :ccc,
    version: "0.1.0",
    elixir: "~> 1.17",
    escript: [main_module: Ccc.CLI, name: "ccc"],
    # ...
  ]
end
```

**`mix escript.build`** produces a standalone `ccc` executable in `elixir/ccc`.
No external dependencies — only `System.cmd/3` and `Port`.

---

## 2. Library API

### `Ccc.CommandSpec`

```elixir
defmodule Ccc.CommandSpec do
  defstruct [:argv, :stdin_text, :cwd, :env]
  # argv: [String.t()]
  # stdin_text: String.t() | nil
  # cwd: String.t() | nil
  # env: %{String.t() => String.t()}
end
```

Builder API matching the Rust fluent style:

```elixir
%CommandSpec{argv: ["opencode", "run", "hello"]}
|> with_stdin("data")
|> with_cwd("/tmp")
|> with_env("KEY", "value")
```

### `Ccc.CompletedRun`

```elixir
defmodule Ccc.CompletedRun do
  defstruct [:argv, :exit_code, :stdout, :stderr]
  # argv: [String.t()]
  # exit_code: non_neg_integer()
  # stdout: String.t()
  # stderr: String.t()
end
```

### `Ccc.Runner`

```elixir
defmodule Ccc.Runner do
  def run(%CommandSpec{} = spec) :: %CompletedRun{}
  def stream(%CommandSpec{} = spec, on_event :: (String.t(), String.t() -> any())) :: %CompletedRun{}
end
```

- `run/1` — uses `System.cmd/3` (blocking, captures all output)
- `stream/2` — uses `Port.open/2` with line-oriented `:line` mode for real stdout/stderr streaming
- Both produce a `%CompletedRun{}`

### `Ccc.PromptSpec`

```elixir
defmodule Ccc.PromptSpec do
  def build(prompt :: String.t()) :: {:ok, %CommandSpec{}} | {:error, String.t()}
end
```

Returns `{:ok, %CommandSpec{argv: ["opencode", "run", trimmed]}}` or `{:error, "prompt must not be empty"}`.

---

## 3. Subprocess Execution

### `run/1` — `System.cmd/3`

```elixir
def run(%CommandSpec{} = spec) do
  {bin, args} = split_argv(spec.argv)
  opts = build_cmd_opts(spec)

  try do
    {stdout, stderr} = System.cmd(bin, args, opts)
    # System.cmd raises on non-zero exit; catch to extract exit_code
    %CompletedRun{argv: spec.argv, exit_code: 0, stdout: stdout, stderr: stderr}
  rescue
    e in [File.Error, ErlangError] ->
      %CompletedRun{argv: spec.argv, exit_code: 1, stdout: "", stderr: format_startup_error(spec, e)}
  catch
    :exit, {status, _} when is_integer(status) ->
      # System.cmd exits with {status, _} on non-zero
      %CompletedRun{argv: spec.argv, exit_code: abs(status), stdout: "", stderr: ""}
  end
end
```

**Problem:** `System.cmd/3` raises `ErlangError` on non-zero exit code with exit status in the payload. Need to `catch :exit` to extract it. For stdout/stderr on failure, we need to use `:into` or capture differently.

**Better approach — use `System.cmd/3` with a custom `:stderr_to_stdout` or avoid `System.cmd` entirely for `run` and use `Port` for both paths:**

### Revised: Port-based for both `run` and `stream`

Use `Port.open({:spawn_executable, bin}, ...)` for full control:

```elixir
defp exec_port(%CommandSpec{} = spec) do
  [bin | args] = spec.argv
  port = Port.open({:spawn_executable, to_charlist(bin)}, [
    :binary, :exit_status,
    :stderr_to_stdout,  # or use :nouse_stdio + fd redirection
    args: Enum.map(args, &to_charlist/1),
    cd: spec.cwd && to_charlist(spec.cwd),
    env: merge_env(spec.env)
  ])
  port
end
```

**Stream** uses `:line` mode, iterating on `receive` with `{:data, port, {flag, line}}` until `{:EXIT_STATUS, ^port, code}`.

**Run** collects all chunks into buffers, then returns `CompletedRun`.

### Error handling

On `:spawn_executable` failure (ENOENT), `Port.open` returns immediately and sends `{:EXIT_STATUS, port, status}`. Check for immediate exit with no data as startup failure.

**Startup failure detection heuristic:** If the port sends `EXIT_STATUS` before any `:data` messages, and the exit code is non-zero, assume startup failure. The error message comes from the OS (via port error reporting).

Actually, `Port.open({:spawn_executable, bad_path}, ...)` does **not** raise — it opens the port and the OS sends exit status. We can detect this by checking if we receive `EXIT_STATUS` before any data. However, the error reason (ENOENT) isn't directly available via Port.

**Alternative:** Attempt a file existence check first, or wrap in a try/catch. In Erlang/Elixir, `Port.open({:spawn_executable, path}, [])` will fail if the path doesn't exist — it actually raises an `ArgumentError` or returns immediately with the port crashing.

**Concrete plan:** Wrap `Port.open` in a try/rescue. If it raises, format the startup error. Otherwise, communicate with the port normally.

```elixir
try do
  port = Port.open({:spawn_executable, to_charlist(bin)}, port_opts)
  communicate(port)
rescue
  ArgumentError ->
    %CompletedRun{argv: spec.argv, exit_code: 1, stdout: "", stderr: "failed to start #{bin}: no such file or directory\n"}
end
```

This matches the cross-language contract where the error format is `"failed to start <argv[0]>: <error>"`.

---

## 4. `ccc` CLI

### Escript entrypoint

**Decision: escript** — simpler than Mix task for a standalone binary. Produces a single executable file.

```elixir
# escript/ccc.ex
defmodule Ccc.CLI do
  def main(argv) do
    case argv do
      [prompt] ->
        case Ccc.PromptSpec.build(prompt) do
          {:ok, spec} ->
            result = Ccc.Runner.run(spec)
            IO.write(result.stdout)
            IO.write(:stderr, result.stderr)
            System.halt(result.exit_code)
          {:error, reason} ->
            IO.write(:stderr, reason <> "\n")
            System.halt(1)
        end
      _ ->
        IO.write(:stderr, "usage: ccc \"<Prompt>\"\n")
        System.halt(1)
    end
  end
end
```

**Why not a Mix task?** Mix tasks require `mix` in PATH and the project source. An escript is a single precompiled binary — identical to how Python, Rust, TypeScript, and C ship their `ccc` binary. This matches the cross-language contract test expectations.

---

## 5. Prompt Trimming & Empty Rejection

```elixir
defmodule Ccc.PromptSpec do
  def build(prompt) do
    trimmed = String.trim(prompt)
    if trimmed == "" do
      {:error, "prompt must not be empty"}
    else
      {:ok, %Ccc.CommandSpec{argv: ["opencode", "run", trimmed]}}
    end
  end
end
```

- `String.trim/1` handles leading/trailing whitespace (spaces, tabs, newlines)
- Empty string and whitespace-only string both produce `""` after trim → rejected
- Matches all other implementations

---

## 6. Error Format

Startup failure: `"failed to start #{argv[0]}: #{error}\n"`

- Only `argv[0]` (the binary name), not the full argv list
- Matches Python/Rust/TypeScript/C behavior
- The contract test checks for `"failed to start"` substring in stderr

---

## 7. Exit Code Forwarding

```elixir
System.halt(result.exit_code)
```

`System.halt/1` terminates the BEAM VM with the given exit code. This is equivalent to Rust's `std::process::exit()` or C's `_exit()`. It bypasses BEAM shutdown hooks, which is the correct behavior for a CLI wrapper — we don't want OTP supervision trees interfering with exit code forwarding.

---

## 8. Test Strategy

### Unit tests — ExUnit

**`test/ccc/prompt_spec_test.exs`:**
- `test "build trims whitespace from prompt"`
- `test "build rejects empty prompt"`
- `test "build rejects whitespace-only prompt"`
- `test "build produces correct argv"`

**`test/ccc/runner_test.exs`:**
- `test "run captures stdout and stderr"`
- `test "run reports startup failure for nonexistent binary"`
- `test "run forwards exit code"`
- `test "run with stdin_text"`
- `test "run with cwd"`
- `test "run with env overrides"`
- `test "stream invokes callback with stdout and stderr"`

**`test/ccc/cli_test.exs`:**
- `test "main with one arg runs successfully"`
- `test "main with empty prompt exits 1"`
- `test "main with no args prints usage"`
- `test "main with multiple args prints usage"`

### `CCC_REAL_OPENCODE` override

In `Ccc.Runner.run/1`, check `System.get_env("CCC_REAL_OPENCODE")` to override the binary in `argv[0]`:

```elixir
defp resolve_bin(argv) do
  case System.get_env("CCC_REAL_OPENCODE") do
    nil -> List.first(argv)
    override -> override
  end
end
```

This allows the cross-language contract tests to use a stub binary, just like the other implementations.

### Cross-language contract test integration

The Elixir escript must be invocable as `elixir/ccc "<Prompt>"`. The contract test file (`tests/test_ccc_contract.py`) needs an Elixir section added:

```python
subprocess.run(
    ["elixir/ccc", PROMPT],
    cwd=ROOT,
    env=env,
    capture_output=True,
    text=True,
    check=False,
)
```

This requires `mix escript.build` to have been run first. Add a build step analogous to the C `make` step.

### Test isolation

- Unit tests: no real subprocess needed for prompt_spec; runner tests use `CCC_REAL_OPENCODE` pointing to a test stub
- CLI tests: test `main/1` function directly with `argv` argument (ExUnit captures IO via `ExUnit.CaptureIO`)
- Integration: escript tests in `test/ccc_test.exs` invoke the built binary via `System.cmd`

---

## 9. Elixir-Specific Design

### Pattern matching

Core to the API — function heads dispatch on struct shape:

```elixir
def run(%CommandSpec{argv: [bin | _]} = spec), do: ...
def build(""), do: {:error, "prompt must not be empty"}
def build(prompt), do: ...
```

The CLI entrypoint uses pattern matching on argv length:

```elixir
def main([prompt]), do: handle_prompt(prompt)
def main(_), do: usage_error()
```

### Pipe operator

Builder API chains via pipes:

```elixir
spec = %Ccc.CommandSpec{argv: ["opencode", "run", "hello"]}
       |> Ccc.CommandSpec.with_stdin("data")
       |> Ccc.CommandSpec.with_cwd("/tmp")
       |> Ccc.CommandSpec.with_env("FOO", "bar")
```

### OTP considerations

- No GenServer, Supervisor, or Application needed for v1 — this is a fire-and-forget CLI wrapper
- `System.halt/1` is used for exit code forwarding; it kills the VM, so no graceful shutdown needed
- Future: if `ccc` grows to support long-running sessions or multiple concurrent runs, a `Task`-based approach or simple `GenServer` could wrap `Port` communication
- The library layer (`Ccc.Runner`) is stateless — pure functions taking a spec, returning a result. No process dictionary, no agents

### Port-based streaming design

```elixir
def stream(%CommandSpec{} = spec, on_event) do
  port = open_port(spec)
  collect_stream(port, on_event, "", "")
end

defp collect_stream(port, on_event, stdout_acc, stderr_acc) do
  receive do
    {^port, {:data, {:eol, line}}} ->
      on_event.("stdout", line <> "\n")
      collect_stream(port, on_event, stdout_acc <> line <> "\n", stderr_acc)
    {^port, {:exit_status, code}} ->
      %CompletedRun{argv: spec.argv, exit_code: code, stdout: stdout_acc, stderr: stderr_acc}
  after
    5000 -> :timeout  # safety
  end
end
```

Note: `:stderr_to_stdout` merges stderr into stdout for simple cases. For true stderr/stdout separation, use a more advanced setup with `:nouse_stdio` and `:parallelism` or OS-level pipe redirection (or `System.cmd` with capture for `run`).

**Decision for v1:** Use `:stderr_to_stdout` for simplicity. If true stderr/stdout separation is needed later, switch to `System.cmd/3` for `run` (which handles stderr separately) and `Port` for `stream`.

### Revised hybrid approach

- **`run/1`:** Use `System.cmd/3` — it handles stdout/stderr separation, exit codes, env, cwd natively. Catch `:exit` for non-zero exit codes.
- **`stream/2`:** Use `Port` with `:line` mode for real streaming. Accept that stderr merge is acceptable for streaming (matches TypeScript behavior).

---

## 10. Parity Gaps

### Full parity targets (must have for v1)

| Feature | Python | Rust | TS | C | Elixir plan |
|---------|--------|------|----|---|-------------|
| build_prompt_spec | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes |
| Runner.stream | yes | yes (non-streaming) | yes | no | yes |
| ccc CLI | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes |
| Stdin/CWD/Env | yes | yes | yes | yes | yes |
| Startup failure | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes |

### Known gaps to address

1. **Contract test integration** — `tests/test_ccc_contract.py` needs Elixir escript added to each test method. Currently only Python/Rust/TS/C are tested.

2. **Build step in CI** — `mix escript.build` must run before contract tests. Add to CI pipeline alongside `cargo build` and `make -C c build/ccc`.

3. **`System.cmd/3` exit code handling** — `System.cmd/3` raises on non-zero exit. Must `catch :exit, {:exit_status, code}` to extract the exit code while also capturing stdout/stderr. This is the trickiest Elixir-specific detail. Alternative: use `System.cmd(bin, args, stderr_to_stdout: true)` and handle via catch.

4. **Port stderr/stdout separation** — Elixir's `Port` doesn't natively separate stdout and stderr. Options:
   - Use `System.cmd/3` for `run` (handles separation)
   - Accept merged streams for `stream` (Rust's `stream` is also non-streaming)
   - Future: use `:exec` library or OS-level fd redirection for true separation

5. **No OTP supervision** — Acceptable for v1 (fire-and-forget CLI). If the project grows toward daemonization or session management, add an Application with a Supervisor.

6. **Elixir runtime startup overhead** — `mix escript.build` produces a binary that boots the BEAM. First invocation is slower than C/Rust but comparable to Python/Node. Acceptable for the use case.

7. **No `with_executor` injection** — Python/Rust support injecting custom executors for testing. In Elixir, achieve this via `CCC_REAL_OPENCODE` env var (sufficient for contract tests) or by passing the execution function as a module attribute/config for unit tests.

### Non-goals (matching README)

- `@alias` expansion
- `+0..+4` context selectors
- `:provider:model` routing
- Config-backed alias/default resolution
- Parser beyond `ccc "<Prompt>"`

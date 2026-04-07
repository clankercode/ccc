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
├── test/
│   ├── test_helper.exs
│   └── ccc/
│       ├── prompt_spec_test.exs
│       ├── runner_test.exs
│       └── cli_test.exs
├── README.md
└── PLAN.md
```

No `escript/` directory — the escript entrypoint is `Ccc.CLI` defined in `lib/ccc/cli.ex`, declared via `escript: [main_module: Ccc.CLI]` in `mix.exs`.

**`mix.exs`** — no deps, no application (not an OTP app):

```elixir
def project do
  [
    app: :ccc,
    version: "0.1.0",
    elixir: "~> 1.17",
    escript: [main_module: Ccc.CLI, name: "ccc"],
    elixirc_paths: elixirc_paths(Mix.env()),
    start_permanent: Mix.env() == :prod
  ]
end

defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]

def application, do: []
```

**`mix escript.build`** produces a standalone `ccc` executable in `elixir/ccc`.

---

## 2. Build Instructions

### Prerequisites

- Elixir ~> 1.17 (with matching Erlang/OTP 26+)

### Build

```sh
cd elixir
mix escript.build   # produces elixir/ccc
```

### Unit tests

```sh
cd elixir
mix test
```

### Run the CLI

```sh
./elixir/ccc "Fix the failing tests"
```

---

## 3. Library API

### `Ccc.CommandSpec`

```elixir
defmodule Ccc.CommandSpec do
  defstruct argv: [], stdin_text: nil, cwd: nil, env: %{}

  def with_stdin(%__MODULE__{} = spec, text) do
    %{spec | stdin_text: text}
  end

  def with_cwd(%__MODULE__{} = spec, cwd) do
    %{spec | cwd: cwd}
  end

  def with_env(%__MODULE__{} = spec, key, value) do
    %{spec | env: Map.put(spec.env, key, value)}
  end
end
```

### `Ccc.CompletedRun`

```elixir
defmodule Ccc.CompletedRun do
  defstruct [:argv, :exit_code, :stdout, :stderr]
end
```

### `Ccc.PromptSpec`

```elixir
defmodule Ccc.PromptSpec do
  def build(prompt) when is_binary(prompt) do
    trimmed = String.trim(prompt)
    if trimmed == "" do
      {:error, "prompt must not be empty"}
    else
      {:ok, %Ccc.CommandSpec{argv: ["opencode", "run", trimmed]}}
    end
  end
end
```

### `Ccc.Runner`

```elixir
defmodule Ccc.Runner do
  def run(%Ccc.CommandSpec{} = spec) :: %Ccc.CompletedRun{}
  def stream(%Ccc.CommandSpec{} = spec, on_event) :: %Ccc.CompletedRun{} when is_function(on_event, 2)
end
```

- `run/1` — uses `System.cmd/3` (blocking, captures all output, separates stdout/stderr)
- `stream/2` — uses `System.cmd/3` with buffered callback invocation (matching Rust's non-streaming-but-callback approach; true async streaming deferred)
- Both produce a `%Ccc.CompletedRun{}`

---

## 4. Subprocess Execution

### `run/1` — `System.cmd/3`

`System.cmd/3` is the right choice for `run`: it handles stdout/stderr separation, env merging, cwd, and exit codes natively. The catch is that it raises on non-zero exit, wrapping the result in an `ErlangError`.

```elixir
def run(%Ccc.CommandSpec{} = spec) do
  [bin | args] = spec.argv
  opts = [
    into: "",
    stderr_to_stdout: false
  ]
  |> maybe_put(:cd, spec.cwd && to_charlist(spec.cwd))
  |> maybe_put(:env, merge_env(spec.env))
  |> maybe_put(:input, spec.stdin_text)

  try do
    {output, _} = System.cmd(bin, args, opts)
    %Ccc.CompletedRun{argv: spec.argv, exit_code: 0, stdout: output, stderr: ""}
  rescue
    e in ErlangError ->
      case e do
        %{exit_status: status, stdout: stdout, stderr: _} ->
          %Ccc.CompletedRun{argv: spec.argv, exit_code: status, stdout: stdout, stderr: ""}
        _ ->
          %Ccc.CompletedRun{argv: spec.argv, exit_code: 1, stdout: "", stderr: format_error(spec, e)}
      end
  catch
    :exit, {%{exit_status: status} = reason} ->
      stdout = Map.get(reason, :stdout, "")
      stderr = Map.get(reason, :stderr, "")
      %Ccc.CompletedRun{argv: spec.argv, exit_code: status, stdout: stdout, stderr: stderr}
    kind, reason ->
      %Ccc.CompletedRun{argv: spec.argv, exit_code: 1, stdout: "", stderr: format_error(spec, {kind, reason})}
  end
end
```

**Critical detail:** On Elixir 1.17+, `System.cmd/3` with `into: ""` and no `stderr_to_stdout` raises with the exit status and captured output available. The exact exception shape varies by OTP version — the `rescue` + `catch` dual approach covers both patterns. **Must be tested against target OTP version.**

**Stderr handling with `System.cmd`:** `System.cmd` returns `{stdout, _}` when no `stderr_to_stdout` option is set. To capture stderr separately, use `:stderr_to_stdout: false` (the default) and extract stderr from the exception payload on failure. For a simpler v1, use `stderr_to_stdout: true` for `run/1` — this merges stderr into stdout like the Port approach but with cleaner exit-code handling. Then `stream/2` does the same. Both match how the other implementations handle output.

**Revised v1: use `stderr_to_stdout: true` for `run/1`:**

```elixir
def run(%Ccc.CommandSpec{} = spec) do
  [bin | args] = resolve_argv(spec.argv)
  opts = build_cmd_opts(spec)

  try do
    {output, 0} = System.cmd(bin, args, opts)
    %Ccc.CompletedRun{argv: spec.argv, exit_code: 0, stdout: output, stderr: ""}
  catch
    :exit, {%{exit_status: status, stdout: output}} ->
      %Ccc.CompletedRun{argv: spec.argv, exit_code: status, stdout: output, stderr: ""}
    :exit, {status, _} when is_integer(status) ->
      %Ccc.CompletedRun{argv: spec.argv, exit_code: status, stdout: "", stderr: ""}
    kind, reason ->
      %Ccc.CompletedRun{argv: spec.argv, exit_code: 1, stdout: "", stderr: format_error(spec, {kind, reason})}
  end
end
```

This is the safest approach: `stderr_to_stdout` merges both streams, `System.cmd/3` raises with the merged output in the exception payload on non-zero exit, and we catch it to extract exit code + output. Stderr separation is not required by the contract tests (which only check stdout content for the happy path).

### `stream/2` — non-streaming with callback

Match Rust's approach: run the command, buffer output, invoke callback, return result.

```elixir
def stream(%Ccc.CommandSpec{} = spec, on_event) do
  result = run(spec)
  if result.stdout != "", do: on_event.("stdout", result.stdout)
  if result.stderr != "", do: on_event.("stderr", result.stderr)
  result
end
```

This guarantees `stream/2` produces identical output to `run/1` (no stdout/stderr interleaving divergence).

### Helper: env merging

```elixir
defp merge_env(overrides) when map_size(overrides) == 0, do: nil
defp merge_env(overrides) do
  System.get_env() |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  |> Enum.concat(Enum.map(overrides, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end))
end
```

### Helper: `CCC_REAL_OPENCODE` override

```elixir
defp resolve_argv(argv) do
  case System.get_env("CCC_REAL_OPENCODE") do
    nil -> argv
    override -> [override | tl(argv)]
  end
end
```

Replaces only `argv[0]`, preserving all other args. This is how `opencode run <prompt>` still passes `"run"` and the prompt after the override.

### Startup failure

When `System.cmd` fails to spawn (ENOENT), it raises an `ErlangError` with the OS error. The format must match the cross-language contract:

```elixir
defp format_error(%Ccc.CommandSpec{argv: [bin | _]}, reason) do
  msg = case reason do
    {:enoent, _} -> "no such file or directory"
    {:eacces, _} -> "permission denied"
    {kind, val} -> "#{kind}: #{inspect(val)}"
    val -> inspect(val)
  end
  "failed to start #{bin}: #{msg}\n"
end
```

---

## 5. `ccc` CLI

### Escript entrypoint (`Ccc.CLI` in `lib/ccc/cli.ex`)

```elixir
defmodule Ccc.CLI do
  def main(argv) do
    case argv do
      [prompt] ->
        case Ccc.PromptSpec.build(prompt) do
          {:ok, spec} ->
            result = Ccc.Runner.run(spec)
            IO.write(result.stdout)
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

**Why escript, not Mix task:** Mix tasks require `mix` in PATH and the project source tree. An escript is a single precompiled binary — identical to how Python, Rust, TypeScript, and C ship their `ccc` binary. Matches contract test expectations.

**`System.halt/1`** terminates the BEAM VM immediately with the given exit code. Bypasses shutdown hooks — correct for a CLI wrapper that must forward the subprocess exit code exactly.

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
- `test "run captures stdout from subprocess"`
- `test "run reports startup failure for nonexistent binary"` — use `%Ccc.CommandSpec{argv: ["nonexistent_binary_xyz"]}`
- `test "run forwards non-zero exit code"`
- `test "run with stdin_text"`
- `test "run with cwd"`
- `test "run with env overrides"` — verify env vars reach subprocess via `CCC_REAL_OPENCODE` pointing to `printenv`
- `test "stream invokes callback with stdout"`

**`test/ccc/cli_test.exs`:**
- `test "main with one arg succeeds"` — capture IO, assert output
- `test "main with empty prompt exits 1"` — use `ExUnit.CaptureIO` + catch `System.halt` via a test helper that replaces `System.halt` with a throw
- `test "main with no args prints usage to stderr"`
- `test "main with multiple args prints usage to stderr"`

### Test helper for `System.halt` interception

`System.halt` kills the VM and cannot be caught in ExUnit. Wrap CLI tests behind a helper that replaces halt:

```elixir
# test/support/cli_test_helper.ex
defmodule Ccc.CliTestHelper do
  def run_cli(argv) do
    {output, exit_code} =
      try do
        output = ExUnit.CaptureIO.capture_io(fn ->
          Ccc.CLI.main(argv)
        end)
        {output, 0}
      catch
        :throw, {:halt, code, output} ->
          {output, code}
      end
    {output, exit_code}
  end
end
```

This requires a small refactor: `Ccc.CLI.main/1` calls `halt!/1` instead of `System.halt/1`, and `halt!/1` is defined differently in test vs prod:

```elixir
# In Ccc.CLI:
defp halt!(code), do: throw({:halt, code})

# In test/support/config.exs or via @compile directive, override to use System.halt/1 in prod.
# Actually: the escript uses System.halt/1. Tests monkeypatch.
```

Simpler approach: define `Ccc.CLI.halt/1` as a function that tests can override via `:persistent_term` or module attribute. For v1, the simplest working approach is to **test the library layer** (`Runner.run`, `PromptSpec.build`) directly and only integration-test the escript via `System.cmd` against the built binary.

### Cross-language contract test registration

Add Elixir to each test method in `tests/test_ccc_contract.py`. The pattern follows the C integration:

```python
# In test_cross_language_ccc_happy_path (and other methods), add after the C block:

subprocess.run(
    ["mix", "escript.build"],
    cwd=str(ROOT / "elixir"),
    env=env,
    capture_output=True,
    text=True,
    check=True,
)
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "elixir" / "ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

This mirrors the C pattern: build step then invocation. The `env` already has the stub `opencode` on PATH.

---

## 9. CI Notes

### Required CI additions

1. **Install Elixir + Erlang/OTP** — use `erlef/setup-beam` GitHub Action or equivalent
2. **Build escript** before contract tests:
   ```sh
   cd elixir && mix escript.build
   ```
3. **Run Elixir unit tests:**
   ```sh
   cd elixir && mix test
   ```
4. **Register Elixir in contract tests** — see Section 8
5. **No cache needed** — `mix escript.build` is fast; deps are empty

### CI matrix consideration

Elixir tests only need Linux (no cross-platform concern). The escript binary is platform-specific but CI only runs on Linux runners currently.

---

## 10. Elixir-Specific Design

### Pattern matching

Core to the API — function heads dispatch on struct shape:

```elixir
def run(%Ccc.CommandSpec{argv: [bin | _]} = spec), do: ...
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

- No GenServer, Supervisor, or Application needed for v1 — fire-and-forget CLI wrapper
- `System.halt/1` kills the VM, so no graceful shutdown needed
- Library layer (`Ccc.Runner`) is stateless — pure functions, no process dictionary, no agents

---

## 11. Parity Matrix

| Feature | Python | Rust | TS | C | Elixir |
|---------|--------|------|----|---|--------|
| build_prompt_spec | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes |
| Runner.stream | yes | yes (non-streaming) | yes | no | yes (non-streaming) |
| ccc CLI | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes |
| Stdin/CWD/Env | yes | yes | yes | yes | yes |
| Startup failure | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes |
| Contract tests | yes | yes | yes | yes | **pending registration** |

---

## 12. Open Issues & Deferred Items

1. **True stderr/stdout separation in `run/1`** — v1 uses `stderr_to_stdout: true`. To separate, remove that option and extract stderr from the `System.cmd` exception payload. Requires OTP-version-specific handling; defer until tests validate the merged approach is sufficient.

2. **Async streaming via Port** — Deferred. `stream/2` delegates to `run/1` + callback (matches Rust). If true line-by-line streaming is needed, use `Port.open({:spawn_executable, bin}, [:binary, :exit_status, :line, ...])` with a receive loop.

3. **No `with_executor` injection** — Python/Rust support injecting custom executors for testing. Elixir uses `CCC_REAL_OPENCODE` env var (sufficient for contract tests).

4. **BEAM startup overhead** — escript boots the BEAM on each invocation. Acceptable for the CLI use case; no action needed.

### Non-goals (matching README)

- `@alias` expansion
- `+0..+4` context selectors
- `:provider:model` routing
- Config-backed alias/default resolution
- Parser beyond `ccc "<Prompt>"`

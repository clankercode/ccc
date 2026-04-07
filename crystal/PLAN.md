# Crystal Implementation Plan

## 0. Build & Run

```sh
# Build the CLI binary
crystal build src/bin/ccc.cr -o ccc              # debug
crystal build src/bin/ccc.cr -o ccc --release     # optimized

# Run unit + integration specs
crystal spec

# Cross-language contract tests (from repo root)
python3 tests/test_ccc_contract.py
```

Requires Crystal >= 1.0. Install via `brew install crystal` (macOS), `apt install crystal` (Debian/Ubuntu), or `shards` (source).

## 1. Shards Package Structure

```
crystal/
  shard.yml
  .gitignore               # ignore /ccc binary, /lib/
  src/
    call_coding_clis.cr      # library entrypoint, re-exports all public types
    command_spec.cr          # CommandSpec struct
    completed_run.cr         # CompletedRun struct
    runner.cr                # Runner class + default executors
    prompt_spec.cr           # build_prompt_spec function
  bin/
    ccc.cr                   # CLI binary entrypoint
  spec/
    command_spec_spec.cr
    completed_run_spec.cr
    prompt_spec_spec.cr
    runner_spec.cr
    ccc_spec.cr              # integration spec for the CLI binary
```

**shard.yml** skeleton:

```yaml
name: call_coding_clis
version: 0.1.0
license: Unlicense
targets:
  ccc:
    main: src/bin/ccc.cr
dependencies: []
development_dependencies: []
```

**.gitignore** (inside `crystal/`):

```
/ccc
/lib/
```

Note: Crystal shards convention places bin entrypoints under `src/bin/`. The library code lives in `src/`. All specs live in `spec/` and are run via `crystal spec`.

## 2. Library API

### CommandSpec (`src/command_spec.cr`)

```crystal
struct CommandSpec
  getter argv : Array(String)
  getter stdin_text : String?
  getter cwd : String?
  getter env : Hash(String, String)

  def initialize(@argv, @stdin_text = nil, @cwd = nil, @env = Hash(String, String).new)
  end

  # Builder-style mutators return self (idiomatic Crystal).
  def with_stdin(text : String) : self
  def with_cwd(dir : String) : self
  def with_env(key : String, value : String) : self
end
```

Mirrors the Rust API. `argv` is `Array(String)` (not `static_array`). `env` defaults to empty hash.

### CompletedRun (`src/completed_run.cr`)

```crystal
struct CompletedRun
  getter argv : Array(String)
  getter exit_code : Int32
  getter stdout : String
  getter stderr : String

  def initialize(@argv, @exit_code, @stdout, @stderr)
  end
end
```

### Runner (`src/runner.cr`)

```crystal
alias StreamCallback = Proc(String, String, Nil)

class Runner
  @run_executor : CommandSpec -> CompletedRun
  @stream_executor : CommandSpec, StreamCallback -> CompletedRun

  def initialize(...)
  def run(spec : CommandSpec) : CompletedRun
  def stream(spec : CommandSpec, &on_event : StreamCallback) : CompletedRun
end
```

Crystal supports alias types and procs natively. `StreamCallback` is `Proc(String, String, Nil)` — takes two strings (stream name, data), returns nil.

**REVIEW NOTE:** The `@run_executor` and `@stream_executor` type declarations above use a shorthand that Crystal may not accept directly. Crystal proc types with arguments require `Proc(ArgTypes, ReturnType)` syntax. The instance variable declarations should be:

```crystal
@run_executor : Proc(CommandSpec, CompletedRun)
@stream_executor : Proc(CommandSpec, Proc(String, String, Nil), CompletedRun)
```

Or use a `typedef`/`alias` for readability:

```crystal
alias RunExecutor = CommandSpec -> CompletedRun
alias StreamExecutorType = CommandSpec, StreamCallback -> CompletedRun

@run_executor : RunExecutor
@stream_executor : StreamExecutorType
```

The default `run_executor` uses `Process.run` (see section 3). The default `stream_executor` delegates to the run executor and fires callbacks — same as the Rust "non-streaming" approach for parity.

For testability, the constructor accepts optional executor procs (same injection pattern as Python/Rust).

### build_prompt_spec (`src/prompt_spec.cr`)

**REVIEW NOTE:** Crystal requires top-level `def` to be wrapped in a module or class for proper namespacing when `require`d. Without a module, `build_prompt_spec` becomes a top-level method that could clash. Use the `CallCodingClis` module:

```crystal
module CallCodingClis
  def self.build_prompt_spec(prompt : String) : CommandSpec
    normalized = prompt.strip
    raise ArgumentError.new("prompt must not be empty") if normalized.empty?
    CommandSpec.new(["opencode", "run", normalized])
  end
end
```

All other public functions (`default_run_executor`, `merge_env`) should also be module methods (`def self.`) or private helpers within the `CallCodingClis` module. The CLI binary references them as `CallCodingClis.build_prompt_spec(...)` and `CallCodingClis::Runner.new`.

### Library Entrypoint (`src/call_coding_clis.cr`)

```crystal
require "./command_spec"
require "./completed_run"
require "./runner"
require "./prompt_spec"
```

Re-exports everything so downstream can `require "call_coding_clis"`.

## 3. Subprocess via Process Stdlib

Crystal's `Process` module provides `Process.run` and `Process.new` (low-level).

### Default run_executor

Use `Process.run` for blocking execution with captured output:

```crystal
def default_run_executor(spec : CommandSpec) : CompletedRun
  argv = spec.argv
  env = merge_env(spec.env)

  return CompletedRun.new(argv: argv, exit_code: 1, stdout: "", stderr: "argv must not be empty\n") if argv.empty?

  binary = ENV["CCC_REAL_OPENCODE"]? || argv[0]
  begin
    process = Process.run(
      binary,
      argv[1..],
      input: Process::Redirect::Pipe,
      output: Process::Redirect::Capture,
      error: Process::Redirect::Capture,
      chdir: spec.cwd,
      env: env
    ) do |process|
      process.input.puts(spec.stdin_text) if spec.stdin_text
      process.close_input
    end
    CompletedRun.new(
      argv: argv,
      exit_code: process.exit_code || 1,
      stdout: process.output.gets_to_end,
      stderr: process.error.gets_to_end
    )
  rescue ex : Errno
    CompletedRun.new(
      argv: argv,
      exit_code: 1,
      stdout: "",
      stderr: "failed to start #{binary}: #{ex.message}\n"
    )
  end
end
```

Key Crystal semantics:
- `Process.run` is blocking. The block form gives access to `Process` IO objects.
- `Process::Redirect::Capture` captures stdout/stderr into `IO::Memory`.
- `Errno` is the base class for system-level errors (like `Errno::ENOENT` for missing binary).
- `process.exit_code` returns `Int32?` — `nil` when terminated by signal, so `|| 1` for safety.
- `ENV["CCC_REAL_OPENCODE"]?` uses the nilable variant (`?`) to return `String?` — returns `nil` if unset (no exception).

**REVIEW FIXES from original:**
- `CCC_REAL_OPENCODE` override moved into `default_run_executor` (replacing `argv[0]` with the override value), not in `build_prompt_spec`. This keeps the library API pure — `build_prompt_spec` always produces `["opencode", "run", ...]`. The Runner layer handles the override, matching the C implementation's approach.
- Guard added for `argv.empty?` to prevent `argv[0]` raise on an empty command.
- Error message now uses `binary` (the potentially-overridden name) instead of `argv[0]`, matching the contract that reports the actual binary that was attempted.

Alternative: use `Process.new` for lower-level control (separate fork, pipe management), but `Process.run` with the block form covers the contract.

**CAVEAT:** `Process.run` block form + `Process::Redirect::Pipe` for input can deadlock if stdin data exceeds the pipe buffer and the child doesn't read. For this project's use case (small prompts piped to `opencode`), this is not a concern. If large stdin support is needed in the future, use `Process.new` with a fiber that writes stdin asynchronously.

### Default stream_executor

Same as Rust: delegates to run_executor, fires callbacks post-hoc.

```crystal
def default_stream_executor(spec : CommandSpec, on_event : StreamCallback) : CompletedRun
  result = default_run_executor(spec)
  on_event.call("stdout", result.stdout) unless result.stdout.empty?
  on_event.call("stderr", result.stderr) unless result.stderr.empty?
  result
end
```

### Env merging

```crystal
def merge_env(overrides : Hash(String, String)) : Hash(String, String)
  env = ENV.to_h
  overrides.each { |k, v| env[k] = v }
  env
end
```

`ENV` in Crystal is a special `Hash(String, String)`-like object. `ENV.to_h` copies it.

## 4. ccc CLI Binary (`src/bin/ccc.cr`)

```crystal
require "call_coding_clis"

args = ARGV
if args.size != 1
  STDERR.puts %(usage: ccc "<Prompt>")
  exit 1
end

begin
  spec = CallCodingClis.build_prompt_spec(args[0])
rescue ex : ArgumentError
  STDERR.puts ex.message
  exit 1
end

result = CallCodingClis::Runner.new.run(spec)
print(result.stdout) unless result.stdout.empty?
STDERR.print(result.stderr) unless result.stderr.empty?
exit(result.exit_code)
```

`ARGV` is a built-in `Array(String)` of command-line arguments (without program name). `STDERR` and `exit` are top-level Kernel methods.

## 5. Prompt Trimming & Empty Rejection

- `String#strip` — Crystal stdlib, identical semantics to Python/Rust. Returns new string with leading/trailing whitespace removed.
- After strip, check `normalized.empty?` (checks `bytesize == 0`).
- On empty: raise `ArgumentError` with message `"prompt must not be empty"`.
- This matches the Python `ValueError` and Rust `Err("prompt must not be empty")` patterns.
- Whitespace-only prompts (e.g., `"   "`) are correctly rejected because `"   ".strip` → `""` → empty.

## 6. Error Format: argv[0] Only

On startup failure (e.g., binary not found), format stderr as:

```
failed to start <argv[0]>: <error message>
```

Where `<argv[0]>` is `spec.argv.first` (just the program name, not the full argv). This matches all other implementations. Trailing newline included.

In Crystal, `Errno` exceptions carry `ex.message` (e.g., `"No such file or directory"`).

## 7. Exit Code Forwarding

- `process.exit_code` from `Process.run` returns `Int32?`.
- If `nil` (signal kill), default to `1` for parity with Python/Rust.
- CLI binary calls `exit(result.exit_code)` which calls `Kernel#exit(status : Int32)`.
- This is the equivalent of Rust's `std::process::exit()` — terminates immediately with the given code.

## 8. Test Strategy

### Crystal Spec (built-in test framework)

Crystal ships with a built-in spec framework (`crystal spec`), no external dependencies needed.

**Unit specs:**

- `spec/prompt_spec_spec.cr` — test `build_prompt_spec`:
  - Valid prompt returns correct argv
  - Empty string raises `ArgumentError`
  - Whitespace-only raises `ArgumentError`
  - Prompt with surrounding whitespace gets trimmed

- `spec/runner_spec.cr` — test `Runner` with injected executor:
  - Inject a fake executor that returns a known `CompletedRun`
  - Verify `run` delegates correctly
  - Verify `stream` fires callbacks
  - Test with `CCC_REAL_OPENCODE` env to run against a real stub binary

- `spec/command_spec_spec.cr` — builder pattern tests
- `spec/completed_run_spec.cr` — struct field access tests

**Integration spec for CLI binary:**

`spec/ccc_spec.cr` — spawn the compiled `ccc` binary via `Process.run`:
- Happy path with `CCC_REAL_OPENCODE` pointing to a stub
- Empty prompt rejection
- Missing argument → usage message
- Whitespace-only prompt rejection
- Startup failure (nonexistent binary) → stderr contains "failed to start"

### CCC_REAL_OPENCODE

Override happens in the Runner's `default_run_executor` (see section 3), not in `build_prompt_spec`. This keeps `build_prompt_spec` pure — it always produces `argv: ["opencode", "run", ...]`. The executor layer replaces `argv[0]` with the value of `ENV["CCC_REAL_OPENCODE"]` if set.

```crystal
binary = ENV["CCC_REAL_OPENCODE"]? || argv[0]
```

This matches the C implementation pattern (ccc.c reads `CCC_REAL_OPENCODE` and uses it as the runner binary).

### Cross-Language Contract Tests

Add Crystal to each test method in `tests/test_ccc_contract.py`. After the existing C block, add:

```python
subprocess.run(
    ["crystal", "build", "crystal/src/bin/ccc.cr", "-o", "crystal/ccc"],
    cwd=ROOT,
    env=env,
    capture_output=True,
    text=True,
    check=True,
)
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "crystal/ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Repeat the same pattern for `test_cross_language_ccc_rejects_empty_prompt`, `test_cross_language_ccc_requires_one_prompt_argument`, and `test_cross_language_ccc_rejects_whitespace_only_prompt`, using the appropriate assertion helper (`assert_rejects_empty`, `assert_rejects_missing_prompt`).

The cross-language tests use `CCC_REAL_OPENCODE` via the stub `opencode` placed on `PATH` — the C implementation demonstrates this pattern. The Crystal binary inherits the `PATH` from the `env` dict, so `opencode_binary` resolution works automatically.

## 9. Crystal-Specific Notes

### Ruby-like Syntax
- Crystal syntax is nearly identical to Ruby. `def`, `end`, `class`, `struct`, `do..end`, `unless`, etc.
- Type annotations are optional on local vars but required on instance vars (`@x : Int32`) and method signatures for public API.
- No semicolons needed. Implicit returns (last expression).

### Compiled
- `crystal build` produces a native binary. No runtime dependency.
- The `ccc` binary is a single statically-linked (usually) executable.
- Compile with `crystal build src/bin/ccc.cr -o ccc --release` for optimized builds.

### Type Inference
- Crystal infers types for local variables: `x = 42` → `x : Int32`.
- Method return types can be explicitly annotated for public API clarity.
- Union types are available: `String?` (nilable), `Int32 | String`.
- Generics/parametric types supported: `Array(String)`, `Hash(String, String)`.

### Fibers (Lightweight Concurrency)
- Crystal uses green threads (fibers) for concurrency — `spawn { ... }`.
- Fibers are cooperative (not preemptive). IO operations yield.
- Could enable true streaming in the future: `Process.new` + `spawn` to read stdout/stderr pipes concurrently.
- For v1 parity, the non-streaming approach (capture-then-callback) matches Rust and is simpler.
- Future enhancement: use `Channel` to stream output line-by-line from spawned fibers reading stdout/stderr.

### Other Crystal Features
- `require` for file inclusion (compile-time, not runtime).
- Macros system for metaprogramming (not needed for this impl).
- `struct` for value types (stack-allocated, copied). Used for `CommandSpec` and `CompletedRun` since they are data carriers.
- `class` for reference types. Used for `Runner` since it holds mutable state (executors).

## 10. CI Notes

Crystal must be installed on CI runners. GitHub Actions:

```yaml
- uses: crystal-lang/install-crystal@v1
```

In cross-language contract tests, gate Crystal behind a feature flag or skip gracefully if `crystal` is not found:

```python
import shutil

HAS_CRYSTAL = shutil.which("crystal") is not None

# In each test method:
if HAS_CRYSTAL:
    subprocess.run(["crystal", "build", ...], ...)
    self.assert_equal_output(subprocess.run([str(ROOT / "crystal/ccc"), ...], ...))
```

This prevents CI failures on runners without Crystal installed.

## 11. Parity Gaps (v1)

| Feature | Status |
|---------|--------|
| `build_prompt_spec` | Full parity |
| `Runner.run` | Full parity |
| `Runner.stream` | Non-streaming parity (same as Rust). True streaming deferred. |
| `ccc` CLI | Full parity |
| Prompt trimming | Full parity (`String#strip`) |
| Empty prompt rejection | Full parity |
| Stdin/CWD/Env support | Full parity |
| Startup failure reporting | Full parity (`Errno` rescue) |
| Exit code forwarding | Full parity (`Kernel#exit`) |
| `CCC_REAL_OPENCODE` | Full parity |
| Cross-language contract tests | Needs addition to `tests/test_ccc_contract.py` |

### Post-v1 Enhancements
- **True streaming**: Use `Process.new` + `spawn` fibers reading stdout/stderr pipes, feeding a `Channel(String)` back to caller. Would match Python/TypeScript streaming behavior.
- **Signal handling**: Forward signals (SIGINT, SIGTERM) to child process.
- **Cross-compile**: Crystal supports cross-compilation to many targets; add Makefile targets.

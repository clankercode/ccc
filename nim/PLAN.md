# Nim Implementation Plan for call-coding-clis

## 1. Project Structure

```
nim/
  nimble.toml          # Nimble package definition
  src/
    call_coding_clis/
      runner.nim        # Runner, CommandSpec, CompletedRun
      prompt_spec.nim   # buildPromptSpec
      cli.nim           # ccc CLI entry point (main proc)
```

Nim convention: one file per module under a directory matching the package name.
The `nimble.toml` declares `bin = @["src/call_coding_clis/cli"]` to produce the `ccc` binary.

The package name in `nimble.toml` will be `call_coding_clis` (underscores, not hyphens -- Nim identifiers).

## 2. Library API

### CommandSpec

```nim
type
  CommandSpec* = object
    argv*: seq[string]
    stdinText*: Option[string]
    cwd*: Option[string]
    env*: StringTableRef
```

Uses `Option[string]` from `std/options` for optional fields. `StringTableRef` from `std/tables` for env overrides (consistent with `putEnv` / `os.getEnv` patterns).

### CompletedRun

```nim
type
  CompletedRun* = object
    argv*: seq[string]
    exitCode*: int
    stdout*: string
    stderr*: string
```

Fields are exported (`*`) for public access. Naming follows existing implementations (snake_case) but Nim convention allows camelCase -- will use camelCase for consistency with Nim idioms while matching the Rust/TS naming of `exitCode`.

### Runner

```nim
type
  StreamCallback* = proc(channel: string, data: string) {.closure.}

  RunExecutor* = proc(spec: CommandSpec): CompletedRun {.closure.}
  StreamExecutor* = proc(spec: CommandSpec, onEvent: StreamCallback): CompletedRun {.closure.}

  Runner* = object
    executor*: RunExecutor
    streamExecutor*: StreamExecutor

proc newRunner*(): Runner
proc run*(self: Runner; spec: CommandSpec): CompletedRun
proc stream*(self: Runner; spec: CommandSpec; onEvent: StreamCallback): CompletedRun
```

`Runner` is an object (value type) with proc fields. The `{.closure.}` pragma allows capturing context. Default executors are set in `newRunner()`.

### buildPromptSpec

```nim
proc buildPromptSpec*(prompt: string): CommandSpec
  ## Trims prompt, raises ValueError on empty/whitespace-only.
  ## Returns CommandSpec with argv = @["opencode", "run", trimmed].
```

Raises `ValueError` on empty prompt, matching Python's behavior. The Rust version returns `Result` but Nim idioms favor exceptions for validation errors.

## 3. Subprocess via osproc

Use `std/osproc` module:

```nim
import std/osproc

let (stdout, exitCode) = execProcess(
  command = spec.argv[0],
  args = spec.argv[1..^1],
  options = {poStdErrToStdOut}  # capture stderr separately with execCmdEx
)
```

For capturing stdout and stderr separately, use `execCmdEx` which returns a tuple `(output: string, exitCode: int)`.

Better approach -- use `execProcess` with `poParentStreams` for streaming, or `osproc.startProcess` for full control:

```nim
var p = startProcess(
  command = spec.argv[0],
  args = spec.argv[1..^1],
  workingDir = spec.cwd.get(""),
  options = {poStdErrToStdOut, poUsePath}
)
```

For capturing both stdout and stderr into separate buffers (required for `CompletedRun`), the best approach is `execCmdEx`:

```nim
let (output, exitCode) = execCmdEx(spec.argv.mapIt(quoteShell(it)).join(" "))
```

However, this merges stdout+stderr. To get them separately, use `startProcess` with pipes:

```nim
var p = startProcess(spec.argv[0], args = spec.argv[1..^1],
  options = {poUsePath})
# Read from p.outputHandle (stdout) and p.errorHandle (stderr) via streams
```

The implementation will wrap `startProcess` to get separate stdout/stderr, matching other implementations.

### Environment merging

```nim
import std/os

for key, val in spec.env:
  putEnv(key, val)
```

Alternatively, pass env via `processEnv` option in `startProcess` (Nim 2.x). Must merge with current process env manually:

```nim
let envTable = processEnv(spec.cwd, mergedEnv)
```

### Startup failure

`startProcess` raises `OSError` if the binary cannot be found. Catch it:

```nim
try:
  discard startProcess(...)
except OSError as e:
  return CompletedRun(
    argv: spec.argv,
    exitCode: 1,
    stdout: "",
    stderr: "failed to start " & spec.argv[0] & ": " & e.msg & "\n"
  )
```

This matches the contract: `"failed to start <argv[0]>: <error>"`.

## 4. ccc CLI Binary

`src/call_coding_clis/cli.nim` contains `proc main()` and is the Nimble binary entry point.

Logic (identical to all other implementations):

1. Parse `paramCount()` and `paramStr()` -- exactly one arg required
2. Trim prompt with `strutils.strip()`
3. Reject empty/whitespace with stderr message + exit 1
4. Check `getEnv("CCC_REAL_OPENCODE")` for test override
5. Build `CommandSpec` with argv = `@[runner, "run", trimmedPrompt]`
6. Run via `Runner`, forward stdout/stderr, call `quit(result.exitCode)`

`quit()` is used instead of `return` to ensure the process exit code is forwarded (same as Rust's `std::process::exit()`).

## 5. Prompt Trimming and Empty Rejection

```nim
import std/strutils

let trimmed = prompt.strip()
if trimmed.len == 0:
  raise newException(ValueError, "prompt must not be empty")
```

`strutils.strip()` handles leading/trailing whitespace (spaces, tabs, newlines).
This matches Python's `str.strip()` and Rust's `str.trim()`.

## 6. Error Format

Startup failure message format (contract requirement):

```
failed to start <argv[0]>: <error>
```

Only `argv[0]`, not the full argv. Example:
- `failed to start nonexistent_binary: The system cannot find the file specified.\n`

## 7. Exit Code Forwarding

```nim
let result = runner.run(spec)
if result.stdout.len > 0:
  write(stdout, result.stdout)
if result.stderr.len > 0:
  write(stderr, result.stderr)
quit(result.exitCode)
```

`quit()` calls C's `exit()` -- essential for forwarding the child's exit code rather than returning from `main()` (which may not work the same way on all platforms in Nim).

## 8. Test Strategy

### Option A: Nim stdlib unittest

```nim
import std/unittest

suite "prompt spec":
  test "trims whitespace":
    check buildPromptSpec("  hello  ").argv == @["opencode", "run", "hello"]

  test "rejects empty":
    expect ValueError:
      discard buildPromptSpec("")
```

### Option B: Contract tests integration

The existing `tests/test_ccc_contract.py` needs a Nim subsection added to each test method. The contract test will:
1. Build the `ccc` binary via `nim c -o:nim/build/ccc nim/src/call_coding_clis/cli.nim`
2. Run it with `subprocess.run(["nim/build/ccc", prompt], ...)`
3. Assert same output/exit codes as other implementations

### CCC_REAL_OPENCODE

The CLI reads `getEnv("CCC_REAL_OPENCODE")` and uses it as argv[0] instead of `"opencode"`. This is already in the contract test stub mechanism.

### Test file location

```
nim/tests/test_runner.nim    # Unit tests (unittest module)
```

Also add Nim entries to `tests/test_ccc_contract.py` alongside Python/Rust/TS/C.

## 9. Nim-Specific Considerations

### Compilation to C

Nim compiles to C via `nim c`. This means:
- Portable to any platform with a C compiler
- No runtime dependency (single binary output)
- `nim c -d:release -o:ccc src/call_coding_clis/cli.nim` produces optimized binary

### Python-like Syntax

Nim's indentation-based syntax and `proc`/`var`/`let` keywords make it approachable for Python devs. The implementation should read similarly to the Python version.

### Macros

Not needed for this implementation. The types and control flow are straightforward. Avoid meta-programming -- keep it simple and readable.

### Pragmas

- `{.raises: [ValueError].}` -- annotate `buildPromptSpec` to declare it raises ValueError
- `{.exportc, dynlib.}` -- if C interop is ever needed, the types can be exported. Not required for v1.
- `{.compile: "runner.c".}` -- not needed; pure Nim implementation

### GC

Nim uses a tracing GC by default (ORC in Nim 2.x). For a short-lived CLI that spawns a subprocess, GC is irrelevant. No special consideration needed.

### String handling

Nim strings are mutable, length-prefixed, UTF-8 compatible. `string` maps directly to what other languages expect. No special encoding handling needed since Nim 2.0 uses UTF-8 internally.

### Option type

`std/options.Option[T]` is used for optional fields. Access via `.get(default)` or `.isSome()`. This maps cleanly to Python's `Optional` and Rust's `Option`.

### StringTableRef for env

`StringTableRef` from `std/tables` is the standard Nim dict type for string keys. Used for the env override map in `CommandSpec`.

## 10. Parity Gaps to Watch For

### Runner.stream -- non-streaming in Rust, real streaming in Python/TS

The Nim implementation should do real streaming via `startProcess` with piped stdout/stderr, reading chunks and invoking the callback. This matches the Python/TS behavior (better than Rust's non-streaming passthrough).

### osproc pipe handling

`startProcess` with `poUsePath` searches PATH. Without it, only absolute paths work. Must include `poUsePath` to match other implementations' behavior of resolving "opencode" from PATH.

### processEnv support

Nim's `startProcess` in newer versions supports `env` parameter. Need to verify the exact Nim 2.x API for passing a custom environment while inheriting the rest from the parent process.

### quit() vs return

Nim's `quit()` bypasses deferred blocks (defer). Use it at the very end of `main()` only. This is analogous to Rust's `std::process::exit()` which also doesn't run destructors.

### Signal handling

If the child process is killed by a signal, `exitCode` from `waitForExit` may be negative (Nim encodes signal as negative). Need to check if this matches expected behavior or if it should be normalized to 1. Other implementations use `code ?? 1` patterns.

### Cross-compilation

Nim compiles via C, so it should work on Linux/macOS/Windows with appropriate C compilers. No Nim-specific platform issues expected for this simple subprocess wrapper.

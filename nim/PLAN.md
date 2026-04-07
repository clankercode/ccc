# Nim Implementation Plan for call-coding-clis

## 1. Project Structure

```
nim/
  nimble.toml                      # Nimble package definition
  src/
    call_coding_clis/
      runner.nim                    # CommandSpec, CompletedRun, Runner
      prompt_spec.nim               # buildPromptSpec
      cli.nim                       # ccc CLI entry point (main proc)
  tests/
    test_runner.nim                 # Unit tests (stdlib unittest)
  build/                            # Created by build; gitignored
```

Nim convention: one file per module under a directory matching the package name.
The `nimble.toml` declares `bin = @["src/call_coding_clis/cli"]` to produce the `ccc` binary.

The package name in `nimble.toml` will be `call_coding_clis` (underscores, not hyphens -- Nim identifiers).

## 2. Library API

### CommandSpec

```nim
import std/options
import std/tables

type
  CommandSpec* = object
    argv*: seq[string]
    stdinText*: Option[string]
    cwd*: Option[string]
    env*: StringTableRef
```

Uses `Option[string]` from `std/options` for optional fields. `StringTableRef` from `std/tables` for env overrides (consistent with `putEnv` / `os.getEnv` patterns). Field names use camelCase (Nim convention).

### CompletedRun

```nim
type
  CompletedRun* = object
    argv*: seq[string]
    exitCode*: int
    stdout*: string
    stderr*: string
```

Fields are exported (`*`) for public access. Naming uses camelCase per Nim convention.

### Runner

```nim
import std/asyncdispatch

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
import std/strutils

proc buildPromptSpec*(prompt: string): CommandSpec =
  let trimmed = prompt.strip()
  if trimmed.len == 0:
    raise newException(ValueError, "prompt must not be empty")
  result = CommandSpec(
    argv: @["opencode", "run", trimmed],
    stdinText: none(string),
    cwd: none(string),
    env: newStringTable()
  )
```

Raises `ValueError` on empty prompt, matching Python's behavior. The error message is `"prompt must not be empty"` -- verified against all existing implementations which emit this exact string.

## 3. Subprocess via osproc

Use `std/osproc` module. For capturing stdout and stderr **separately** into `CompletedRun`, use `startProcess` with pipes:

```nim
import std/osproc

proc defaultRun(spec: CommandSpec): CompletedRun =
  let workingDir = if spec.cwd.isSome(): spec.cwd.get() else: getCurrentDir()

  # Build merged environment
  var envSeq: seq[string] = @[]
  for k, v in osEnvPairs():
    envSeq.add(k & "=" & v)
  for k, v in spec.env:
    envSeq.add(k & "=" & v)

  try:
    var p = startProcess(
      command = spec.argv[0],
      args = spec.argv[1..^1],
      workingDir = workingDir,
      env = envSeq,
      options = {poUsePath}
    )
  except OSError as e:
    return CompletedRun(
      argv: spec.argv,
      exitCode: 1,
      stdout: "",
      stderr: "failed to start " & spec.argv[0] & ": " & e.msg & "\n"
    )
```

### Pipe reading for separate stdout/stderr

`startProcess` gives access to `p.outputHandle` (stdout) and `p.errorHandle` (stderr). Read them via `std/streams`:

```nim
import std/streams

let stdoutData = p.outputHandle.readAll()
let stderrData = p.errorHandle.readAll()
let exitCode = p.waitForExit()
p.close()
```

Note: `readAll` on a `FileHandle` requires wrapping it or using a stream adapter. The actual implementation must read both handles **concurrently** (or read one fully before the other) to avoid deadlocks when buffer sizes are exceeded. For the `run` (non-streaming) path where we collect all output, reading stdout fully then stderr is acceptable for typical CLI tool output sizes. For `stream`, see Section 8.

### Environment merging

The `startProcess` `env` parameter in Nim 2.x accepts a `seq[string]` of `"KEY=VALUE"` entries. This **replaces** the entire environment, so the implementation must merge the current process env with `spec.env` overrides before passing it:

```nim
var envSeq: seq[string] = @[]
for k, v in osEnvPairs():
  envSeq.add(k & "=" & v)
for k, v in spec.env:
  envSeq.add(k & "=" & v)
```

This matches Python's `_merged_env` pattern exactly.

### Startup failure

`startProcess` raises `OSError` if the binary cannot be found. Catch it:

```nim
try:
  var p = startProcess(...)
except OSError as e:
  return CompletedRun(
    argv: spec.argv,
    exitCode: 1,
    stdout: "",
    stderr: "failed to start " & spec.argv[0] & ": " & e.msg & "\n"
  )
```

This matches the contract: `"failed to start <argv[0]>: <error>"`.

### Signal exit code normalization

If the child process is killed by a signal, `waitForExit` may return a negative exit code (Nim encodes signal as negative). Normalize to 1 to match other implementations:

```nim
let rawExit = p.waitForExit()
let exitCode = if rawExit < 0: 1 else: rawExit
```

This is analogous to the C implementation's `WIFEXITED(status) ? WEXITSTATUS(status) : 1`.

### poUsePath

Must include `poUsePath` in `startProcess` options so that `argv[0]` (e.g. `"opencode"`) is resolved from `PATH`, matching all other implementations. Without this flag, only absolute paths would work.

## 4. ccc CLI Binary

`src/call_coding_clis/cli.nim` contains `proc main()` and is the Nimble binary entry point.

Logic (identical to all other implementations):

1. Parse `paramCount()` and `paramStr()` -- exactly one arg required
2. On wrong arg count: write `usage: ccc "<Prompt>"\n` to stderr, exit 1
3. Trim prompt with `strutils.strip()`
4. Reject empty/whitespace with stderr message + exit 1
5. Check `getEnv("CCC_REAL_OPENCODE")` for test override; default to `"opencode"`
6. Build `CommandSpec` with argv = `@[runner, "run", trimmedPrompt]`
7. Run via `Runner`, forward stdout/stderr, call `quit(result.exitCode)`

```nim
import std/os

proc main() =
  if paramCount() != 1:
    write(stderr, "usage: ccc \"<Prompt>\"\n")
    quit(1)

  let prompt = paramStr(1)

  try:
    let spec = buildPromptSpec(prompt)
    let runner = getEnv("CCC_REAL_OPENCODE")
    if runner.len > 0:
      spec.argv[0] = runner

    let result = Runner().run(spec)
    if result.stdout.len > 0:
      write(stdout, result.stdout)
    if result.stderr.len > 0:
      write(stderr, result.stderr)
    quit(result.exitCode)
  except ValueError as e:
    write(stderr, e.msg & "\n")
    quit(1)

when isMainModule:
  main()
```

Key details:
- The usage message is `usage: ccc "<Prompt>"` (with quotes around `<Prompt>`) -- verified against Python, Rust, and TS implementations.
- `quit()` bypasses deferred blocks (`defer`); use it only at the very end of `main()`. This is analogous to Rust's `std::process::exit()`.
- The `CCC_REAL_OPENCODE` override replaces `argv[0]` (the runner name), not the full argv. It's the same pattern as C's `getenv("CCC_REAL_OPENCODE")`.

## 5. Prompt Trimming and Empty Rejection

```nim
import std/strutils

let trimmed = prompt.strip()
if trimmed.len == 0:
  raise newException(ValueError, "prompt must not be empty")
```

`strutils.strip()` handles leading/trailing whitespace (spaces, tabs, newlines). This matches Python's `str.strip()` and Rust's `str.trim()`.

The empty-prompt stderr output must be exactly `prompt must not be empty\n` to match the contract tests.

## 6. Error Format

Startup failure message format (contract requirement):

```
failed to start <argv[0]>: <error>
```

Only `argv[0]`, not the full argv. Example:
- `failed to start nonexistent_binary: The system cannot find the file specified.\n`

The trailing newline is required -- all other implementations include it.

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

## 8. Stream Implementation

The Nim implementation should do **real streaming** via `startProcess` with piped stdout/stderr, reading chunks and invoking the callback. This matches the Python/TS behavior (better than Rust's non-streaming passthrough).

```nim
proc defaultStream(spec: CommandSpec, onEvent: StreamCallback): CompletedRun =
  let workingDir = if spec.cwd.isSome(): spec.cwd.get() else: getCurrentDir()
  var envSeq = buildEnvSeq(spec.env)

  try:
    var p = startProcess(
      command = spec.argv[0],
      args = spec.argv[1..^1],
      workingDir = workingDir,
      env = envSeq,
      options = {poUsePath}
    )
  except OSError as e:
    let errMsg = "failed to start " & spec.argv[0] & ": " & e.msg & "\n"
    onEvent("stderr", errMsg)
    return CompletedRun(
      argv: spec.argv,
      exitCode: 1,
      stdout: "",
      stderr: errMsg
    )

  # Read stdout and stderr concurrently using async or threads to avoid deadlock
  # For correctness, use select/poll or async file reading.
  # Practical approach: read both fully (acceptable for CLI tool output),
  # then invoke callbacks with accumulated data.
  var stdoutBuf = newStringOfCap(4096)
  var stderrBuf = newStringOfCap(4096)

  var pStdout = p.outputHandle
  var pStderr = p.errorHandle

  let exitCode = p.waitForExit()
  stdoutBuf = pStdout.readAll()
  stderrBuf = pStderr.readAll()
  p.close()

  if stdoutBuf.len > 0:
    onEvent("stdout", stdoutBuf)
  if stderrBuf.len > 0:
    onEvent("stderr", stderrBuf)

  let normalizedExit = if exitCode < 0: 1 else: exitCode
  return CompletedRun(
    argv: spec.argv,
    exitCode: normalizedExit,
    stdout: stdoutBuf,
    stderr: stderrBuf
  )
```

**Note on true streaming vs buffered:** The above collects all output then fires callbacks. This matches Python's `_default_stream_executor` (which calls `communicate()` and then fires callbacks). True incremental streaming with line/chunk callbacks requires async I/O (`asyncdispatch` + `asyncnet` or threads with `io_selector`), which is significant complexity for minimal gain in this CLI tool. The buffered approach satisfies the contract and matches Python's behavior. If real-time streaming is needed later, it can be added as an optimization.

## 9. nimble.toml

```toml
[package]
name = "call_coding_clis"
version = "0.1.0"
author = "call-coding-clis contributors"
description = "Nim implementation of call-coding-clis"
license = "Unlicense"

[bin]
ccc = "src/call_coding_clis/cli"

[dependencies]

[task]
test = "nim c -r -o:build/test_runner tests/test_runner.nim"

[target."c".cCompiler]
options.always = "-w"
```

Key points:
- `bin` produces a `ccc` binary
- The `test` task compiles and runs the unit tests
- No external dependencies required -- only stdlib modules

## 10. Build Instructions

### Prerequisites

- Nim 2.0+ (install via [choosenim](https://github.com/nim-lang/choosenim) or system package manager)
- A C compiler (gcc, clang, or MSVC) -- Nim compiles to C

### Build the ccc binary

```bash
# From repo root
cd nim
nimble build                    # Produces bin/ccc
# OR directly:
nim c -d:release -o:build/ccc src/call_coding_clis/cli.nim
```

### Run unit tests

```bash
cd nim
nimble test
# OR:
nim c -r -o:build/test_runner tests/test_runner.nim
```

### Run cross-language contract tests

```bash
# From repo root -- builds the Nim binary first, then runs Python contract tests
nim c -d:release -o:nim/build/ccc nim/src/call_coding_clis/cli.nim
python3 -m pytest tests/test_ccc_contract.py -v
```

## 11. CI Notes

### GitHub Actions (if/when CI is added)

The Nim binary can be built in CI with:

```yaml
- name: Install Nim
  uses: jiro4989/setup-nim-action@v2
  with:
    nim-version: "2.0"

- name: Build Nim ccc
  run: nim c -d:release -o:nim/build/ccc nim/src/call_coding_clis/cli.nim

- name: Run Nim unit tests
  run: nim c -r -o:nim/build/test_runner nim/tests/test_runner.nim

- name: Run cross-language contract tests
  run: python3 -m pytest tests/test_ccc_contract.py -v
```

Nim compiles to C, so it needs a C compiler in CI. `ubuntu-latest` runners include gcc by default. For macOS, Xcode's clang works. For Windows, MSVC or mingw works.

### Adding Nim to existing CI

If a CI workflow already exists for other languages, add the Nim build/test steps alongside them. The contract test file (`tests/test_ccc_contract.py`) must be updated with Nim entries -- see Section 12.

## 12. Cross-Language Test Registration

The existing `tests/test_ccc_contract.py` needs a Nim subsection added to each of the four test methods. The pattern follows the C implementation (compile, then run binary).

### Changes to `tests/test_ccc_contract.py`

In each test method, after the C block, add:

**Build step** (before any test assertions):

```python
subprocess.run(
    ["nim", "c", "-d:release", "-o:" + str(ROOT / "nim" / "build" / "ccc"),
     str(ROOT / "nim" / "src" / "call_coding_clis" / "cli.nim")],
    cwd=ROOT,
    env=env,
    capture_output=True,
    text=True,
    check=True,
)
```

**Happy path assertion** (in `test_cross_language_ccc_happy_path`):

```python
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "nim" / "build" / "ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

**Empty prompt assertion** (in `test_cross_language_ccc_rejects_empty_prompt`):

```python
self.assert_rejects_empty(
    subprocess.run(
        [str(ROOT / "nim" / "build" / "ccc"), ""],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

**Missing prompt assertion** (in `test_cross_language_ccc_requires_one_prompt_argument`):

```python
self.assert_rejects_missing_prompt(
    subprocess.run(
        [str(ROOT / "nim" / "build" / "ccc")],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

**Whitespace-only prompt assertion** (in `test_cross_language_ccc_rejects_whitespace_only_prompt`):

```python
self.assert_rejects_empty(
    subprocess.run(
        [str(ROOT / "nim" / "build" / "ccc"), whitespace_prompt],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

The `nim/build/` directory must be created before building. The build command should ensure it exists (add `os.makedirs("nim/build", exist_ok=True)` in the test setup, or add `mkdir -p` before the nim build command, or rely on nim creating parent dirs).

## 13. Test Strategy

### Unit tests (nim/tests/test_runner.nim)

```nim
import std/unittest
import call_coding_clis/prompt_spec
import call_coding_clis/runner

suite "prompt spec":
  test "trims whitespace":
    let spec = buildPromptSpec("  hello  ")
    check spec.argv == @["opencode", "run", "hello"]

  test "trims tabs and newlines":
    let spec = buildPromptSpec("\t\nhello\n\t")
    check spec.argv == @["opencode", "run", "hello"]

  test "rejects empty string":
    expect ValueError:
      discard buildPromptSpec("")

  test "rejects whitespace only":
    expect ValueError:
      discard buildPromptSpec("   \t\n  ")

  test "error message is correct":
    try:
      discard buildPromptSpec("")
      check false
    except ValueError as e:
      check e.msg == "prompt must not be empty"

suite "runner":
  test "run captures exit code":
    let spec = CommandSpec(
      argv: @["true"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let result = Runner().run(spec)
    check result.exitCode == 0

  test "run captures stdout":
    let spec = CommandSpec(
      argv: @["echo", "hello"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let result = Runner().run(spec)
    check result.stdout.strip() == "hello"

  test "run handles startup failure":
    let spec = CommandSpec(
      argv: @["nonexistent_binary_xyz_123"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let result = Runner().run(spec)
    check result.exitCode == 1
    check "failed to start nonexistent_binary_xyz_123" in result.stderr
```

The unit tests use `true`/`echo`/`false` (standard Unix commands available on all platforms with CI) for basic runner testing. Platform-specific tests (like nonexistent binary) are cross-platform safe because `startProcess` will fail consistently.

### Contract tests integration

See Section 12 above for the exact code to add to `tests/test_ccc_contract.py`.

### CCC_REAL_OPENCODE

The CLI reads `getEnv("CCC_REAL_OPENCODE")` and uses it as `argv[0]` instead of `"opencode"`. This is already exercised by the contract test stub mechanism (the `_write_opencode_stub` helper writes a shell script to a temp `bin/opencode` and adds it to PATH; the contract tests exercise the real binary resolution path, not the override path).

## 14. Nim-Specific Considerations

### Compilation to C

Nim compiles to C via `nim c`. This means:
- Portable to any platform with a C compiler
- No runtime dependency (single binary output)
- `nim c -d:release -o:ccc src/call_coding_clis/cli.nim` produces optimized binary

### Python-like Syntax

Nim's indentation-based syntax and `proc`/`var`/`let` keywords make it approachable for Python devs. The implementation should read similarly to the Python version.

### GC

Nim uses a tracing GC by default (ORC in Nim 2.x). For a short-lived CLI that spawns a subprocess, GC is irrelevant. No special consideration needed.

### String handling

Nim strings are mutable, length-prefixed, UTF-8 compatible. `string` maps directly to what other languages expect. No special encoding handling needed since Nim 2.0 uses UTF-8 internally.

### Option type

`std/options.Option[T]` is used for optional fields. Access via `.get(default)` or `.isSome()`. This maps cleanly to Python's `Optional` and Rust's `Option`.

### StringTableRef for env

`StringTableRef` from `std/tables` is the standard Nim dict type for string keys. Used for the env override map in `CommandSpec`.

### {.raises.} annotations

Annotate `buildPromptSpec` with `{.raises: [ValueError].}` to declare it raises ValueError. This is good practice in Nim but not strictly required for this project.

### No macros needed

The types and control flow are straightforward. Avoid meta-programming -- keep it simple and readable.

### quit() vs return

Nim's `quit()` bypasses deferred blocks (`defer`). Use it at the very end of `main()` only. This is analogous to Rust's `std::process::exit()` which also doesn't run destructors.

## 15. Parity Gaps to Watch For

### Runner.stream -- non-streaming in Rust, real streaming in Python/TS

The Nim implementation does buffered streaming (collects all output, then fires callbacks). This matches Python's `_default_stream_executor` behavior exactly. See Section 8.

### osproc pipe handling

`startProcess` with `poUsePath` searches PATH. Without it, only absolute paths work. Must include `poUsePath` to match other implementations' behavior of resolving "opencode" from PATH.

### processEnv support

Nim's `startProcess` accepts an `env: seq[string]` parameter (Nim 2.x). This **replaces** the entire environment, so merging with `osEnvPairs()` is required. See Section 3.

### startProcess env parameter type

In Nim 2.x, the `env` parameter of `startProcess` is `seq[string]` (each entry `"KEY=VALUE"`). Verify this against the exact Nim version's `std/osproc` API at implementation time. If the parameter is `StringTableRef` instead, adapt accordingly (unlikely in Nim 2.0+).

### Cross-compilation

Nim compiles via C, so it works on Linux/macOS/Windows with appropriate C compilers. No Nim-specific platform issues expected for this simple subprocess wrapper.

## 16. .gitignore addition

Add to `nim/.gitignore` (or root `.gitignore` if preferred):

```
nim/build/
nim/nimblecache/
```

## 17. Feature Parity

| Feature | Python | Rust | TypeScript | C | Nim (planned) |
|---------|--------|------|------------|---|---------------|
| build_prompt_spec | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes |
| Runner.stream | yes | yes (non-streaming) | yes | no | yes (buffered) |
| ccc CLI | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes |
| Stdin/CWD/Env support | yes | yes | yes | yes | yes |
| Startup failure reporting | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes |
| CCC_REAL_OPENCODE | yes | yes | yes | yes | yes |

## 18. Self-Contained Implementation Checklist

This plan is fully implementable without reading any other language's source code. All contract requirements are specified inline:

- [ ] `nimble.toml` with package metadata and bin entry
- [ ] `CommandSpec` type with argv, stdinText, cwd, env
- [ ] `CompletedRun` type with argv, exitCode, stdout, stderr
- [ ] `Runner` type with `run` and `stream` methods
- [ ] `buildPromptSpec` with trimming and empty rejection
- [ ] Subprocess execution via `startProcess` with separate stdout/stderr capture
- [ ] Environment merging (parent env + spec.env overrides)
- [ ] Startup failure catching with `"failed to start <argv[0]>: <error>\n"` format
- [ ] Signal exit code normalization (negative -> 1)
- [ ] `ccc` CLI binary with arg parsing, usage message, CCC_REAL_OPENCODE support
- [ ] Exit code forwarding via `quit()`
- [ ] Unit tests in `tests/test_runner.nim`
- [ ] Registration in `tests/test_ccc_contract.py` (4 test methods)
- [ ] Build instructions and CI notes

# Go Implementation Plan for call-coding-clis

## 1. Module Structure

```
go/
  go.mod                # module call-coding-clis/go
  ccc.go                # CommandSpec, CompletedRun, Runner, BuildPromptSpec
  ccc_test.go           # library unit tests
  cmd/
    ccc/
      main.go           # CLI binary entrypoint
      main_test.go      # CLI integration tests (with build tag //go:build integration)
```

Single package `ccc` for the library, with `cmd/ccc/` as the CLI binary subdirectory. `cmd/ccc/main.go` uses `package main` and imports `call-coding-clis/go` (relative import `../..` is not valid — use the module path).

## 2. Library API — Go Structs

```go
package ccc

type CommandSpec struct {
    Argv      []string
    StdinText string
    Cwd       string
    Env       map[string]string
}
```

- `StdinText` empty string (zero value) means no stdin — checked via `spec.StdinText != ""` before piping.
- `Cwd` empty string means inherit current directory.
- `Env` nil or empty map means inherit all of `os.Environ()`.

```go
type CompletedRun struct {
    Argv     []string
    ExitCode int
    Stdout   string
    Stderr   string
}
```

```go
type StreamCallback func(stream string, data string)
```

```go
type Runner struct {
    executor       func(CommandSpec) CompletedRun
    streamExecutor func(CommandSpec, StreamCallback) CompletedRun
}
```

- `NewRunner() *Runner` — returns a Runner with `os/exec`-based defaults.
- `(*Runner).Run(spec CommandSpec) CompletedRun`
- `(*Runner).Stream(spec CommandSpec, onEvent StreamCallback) CompletedRun`
- Test injection: `RunWithExecutor(func(CommandSpec) CompletedRun) *Runner` and `RunWithStreamExecutor(func(CommandSpec, StreamCallback) CompletedRun) *Runner`.
- `Default()` via a nil `Runner` receiver — falls through to `NewRunner()`.

```go
func BuildPromptSpec(prompt string) (CommandSpec, error)
```

- Trims via `strings.TrimSpace`.
- Returns `fmt.Errorf("prompt must not be empty")` on empty/whitespace-only input.
- Returns `CommandSpec{Argv: []string{"opencode", "run", trimmed}}`.

## 3. Subprocess via `os/exec`

### `Run` path

1. **Validate**: if `spec.Argv` is nil or empty, return `CompletedRun{ExitCode: 1, Stderr: "no command provided\n"}`.
2. Construct `exec.Cmd` from `spec.Argv[0]` (program) and `spec.Argv[1:]` (args).
3. Set `cmd.Dir = spec.Cwd` if non-empty.
4. Build environment: iterate `os.Environ()`, split on first `=`, overlay `spec.Env` entries, set `cmd.Env`. **Do not** use `os.ExpandEnv` — just direct key-value lookup.
5. If `spec.StdinText != ""`, set `cmd.Stdin = strings.NewReader(spec.StdinText)`.
6. Call `cmd.Output()` — keeps stdout/stderr separate.
7. On error from `cmd.Output()`: if the error is a `*exec.ExitError`, extract stdout/stderr from its fields and set `ExitCode` from `exitError.ExitCode()`. If the error is `*os.PathError` or `*fs.PathError` (binary not found / permission denied), return `CompletedRun{Argv: spec.Argv, ExitCode: 1, Stderr: fmt.Sprintf("failed to start %s: %s\n", spec.Argv[0], err)}`.
8. On successful completion, `ExitCode` is `0`. For signal-killed processes caught as `ExitError`, `ExitCode()` returns -1 — normalize to 1 to match Rust (`unwrap_or(1)`) and C (`WIFEXITED` guard).
9. Use `string(stdoutBytes)` / `string(stderrBytes)` — do not assume UTF-8, match Rust's `String::from_utf8_lossy` by converting raw bytes.

**Important**: `cmd.Output()` calls `cmd.Start()` then `cmd.Wait()`. The error can be an `*exec.ExitError` (non-zero exit) or a startup error. Use type assertion `errors.As` to distinguish. Do not call `cmd.CombinedOutput()` — stdout/stderr must remain separate.

### `Stream` path

1. Construct `exec.Cmd` same as `Run`.
2. Call `cmd.StdoutPipe()` and `cmd.StderrPipe()` **before** `cmd.Start()`. Handle errors from either pipe call as startup failures.
3. Call `cmd.Start()`. On error, return startup-failure `CompletedRun`.
4. Use a `sync.WaitGroup` with count 2 (stdout reader + stderr reader). Each goroutine:
   - Creates a `bufio.Scanner` on the pipe.
   - Loops `scanner.Scan()`, calling `onEvent("stdout", scanner.Text())` or `onEvent("stderr", scanner.Text())`.
   - After loop exits, checks `scanner.Err()` and appends error info if non-nil.
   - Calls `wg.Done()`.
5. If `spec.StdinText != ""`, write stdin in a third goroutine: `io.WriteString(cmd.Stdin, spec.StdinText)` then `cmd.Stdin.Close()`. **Must** close stdin before waiting or the child blocks on stdin reads.
6. `cmd.Wait()` in the main goroutine.
7. `wg.Wait()` to ensure all readers complete before accessing accumulated buffers.
8. Build `CompletedRun` from accumulated stdout/stderr strings. Normalize exit code (signal → 1).

**Pipe deadlock risk**: Must read stdout and stderr concurrently via goroutines. Reading one pipe then the other will deadlock if the child fills the OS pipe buffer (typically 64KB) on the unread pipe. The goroutine-per-pipe pattern avoids this.

**Stdin close ordering**: Close `cmd.Stdin` before `cmd.Wait()` to signal EOF to the child process, otherwise processes that read stdin will hang.

## 4. `ccc` CLI Binary (`cmd/ccc/main.go`)

```sh
go build -o ccc ./cmd/ccc
```

Logic mirrors `c/src/ccc.c` (the simplest reference):

1. Parse `os.Args[1:]`.
2. If `len(args) != 1`: print `usage: ccc "<Prompt>"\n` to stderr, `os.Exit(1)`.
3. Call `ccc.BuildPromptSpec(args[0])`. On error, print error + newline to stderr, `os.Exit(1)`.
4. Respect `CCC_REAL_OPENCODE` env var: if set, replace `spec.Argv[0]` with its value (before calling `Run`). See `c/src/ccc.c:48-51` for the pattern.
5. Run `ccc.NewRunner().Run(spec)`.
6. If `result.Stdout != ""`, print to stdout via `os.Stdout.WriteString(result.Stdout)` — no trailing newline added.
7. If `result.Stderr != ""`, print to stderr via `os.Stderr.WriteString(result.Stderr)`.
8. `os.Exit(result.ExitCode)`.

**Note**: The CLI does **not** use `CCC_REAL_OPENCODE` as an `Env` override on the spec — it replaces `spec.Argv[0]` directly. This matches the C implementation (`ccc.c:48-53`) and avoids surprising env-var leaking into the child.

## 5. Prompt Trimming

- `strings.TrimSpace(prompt)` — handles spaces, tabs, newlines, Unicode whitespace.
- Empty check: `trimmed == ""`.
- Return `fmt.Errorf("prompt must not be empty")` — matches all other implementations.

## 6. Error Format: `argv[0]` Only

On subprocess startup failure:
```
failed to start <argv[0]>: <os/exec error message>
```

Trailing newline included. Use `spec.Argv[0]` only, not the full argv slice. This matches Python, Rust, and C implementations. Guard against nil/empty `Argv` — use `"(unknown)"` fallback matching Rust's pattern (`lib.rs:155`).

## 7. Exit Code Forwarding

- CLI calls `os.Exit(result.ExitCode)` directly.
- No wrapping or post-processing of the exit code.
- For signal-killed processes, `ProcessState.ExitCode()` returns -1 — normalize to 1.
- Implementation: `if code := cmd.ProcessState.ExitCode(); code >= 0 { return code }; return 1`.

## 8. Test Strategy

**Unit tests** (`ccc_test.go`):

- `TestBuildPromptSpec_Valid` — verify argv is `["opencode", "run", "foo bar"]`.
- `TestBuildPromptSpec_Empty` — verify error message contains "prompt must not be empty".
- `TestBuildPromptSpec_WhitespaceOnly` — verify error returned.
- `TestBuildPromptSpec_TrimsWhitespace` — verify leading/trailing spaces removed.
- `TestRunner_NonexistentBinary` — run spec with argv `["__nonexistent_binary_xyz__"]`, assert stderr contains `"failed to start"`, exit_code is 1.
- `TestRunner_ExitCodeForwarding` — run `["sh", "-c", "exit 42"]`, assert `ExitCode == 42`.
- `TestRunner_StdinPassed` — inject executor, verify `StdinText` is wired through.
- `TestRunner_EnvOverride` — inject executor, verify merged env contains override.
- `TestRunner_NilArgv` — verify graceful failure with nil Argv.
- `TestStream_LineByLine` — run a script that prints multiple lines, verify callback fires per line.
- `TestStream_AccumulatesOutput` — verify returned `CompletedRun` has full stdout/stderr.

**Executor injection for testing**:

- `RunWithExecutor` accepts a `func(CommandSpec) CompletedRun` to avoid requiring real subprocess execution in unit tests.

**`CCC_REAL_OPENCODE` env var**:

- In `cmd/ccc/main.go`, check `os.Getenv("CCC_REAL_OPENCODE")` and replace `spec.Argv[0]` if set.
- This allows `tests/test_ccc_contract.py` to point the Go binary at a fake/test opencode.

**Contract tests**:

- Build the `ccc` binary: `go build -o go/ccc ./cmd/ccc`.
- Run the existing `tests/test_ccc_contract.py` — add a Go section to each test method that invokes the built binary.

**Running**:

```sh
cd go && go test ./...
```

Integration tests (require build):
```sh
cd go && go test ./cmd/ccc/ -tags=integration
```

## 9. Build Instructions

```sh
cd go
go build ./...                  # compile all packages (library + binary)
go build -o ccc ./cmd/ccc      # produce standalone ccc binary
go test ./...                   # run unit tests
go vet ./...                    # static analysis
```

**Minimum Go version**: 1.21 (for `log/slog`, `cmp`, `slices` stdlib packages — though this project doesn't need them, 1.21 is a reasonable floor).

**No external dependencies** — `os`, `os/exec`, `strings`, `fmt`, `bufio`, `sync`, `io` are all stdlib.

## 10. CI Notes

The Go implementation should be added to CI alongside existing languages. Pattern follows the C implementation:

1. **Lint/Vet**: `cd go && go vet ./...`
2. **Test**: `cd go && go test ./...`
3. **Build**: `cd go && go build -o ccc ./cmd/ccc`
4. **Contract tests**: Build the binary, then run `tests/test_ccc_contract.py` which will invoke it.
5. Add a Go section to each contract test method in `tests/test_ccc_contract.py` (see section 11).

**No CGO required** — pure Go, cross-compiles trivially (`GOOS=linux GOARCH=amd64 go build ...`).

## 11. Cross-Language Test Registration

Add Go to each test method in `tests/test_ccc_contract.py`. Pattern:

```python
# Build (at top of each test method, alongside C build):
subprocess.run(
    ["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"],
    cwd=str(ROOT / "go"),
    env=env,
    capture_output=True,
    text=True,
    check=True,
)

# Invoke (alongside other language invocations):
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "go" / "ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

All four test methods need the Go addition:
- `test_cross_language_ccc_happy_path`
- `test_cross_language_ccc_rejects_empty_prompt`
- `test_cross_language_ccc_requires_one_prompt_argument`
- `test_cross_language_ccc_rejects_whitespace_only_prompt`

## 12. Go-Specific Design Decisions

**Goroutines for streaming**:

The `Stream` method is where Go shines. Use `bufio.Scanner` in two goroutines reading stdout and stderr pipes concurrently. A `sync.WaitGroup` coordinates completion. This is genuinely streaming (line-by-line), unlike the Rust implementation which buffers everything and calls back at the end.

**Implicit interfaces**:

No interface definitions needed for `StreamCallback` — it's just a `func(string, string)`. The executor injection uses function values directly (Go's first-class functions). No `Executor` trait/interface required.

**Error values**:

- `BuildPromptSpec` returns `(CommandSpec, error)` — idiomatic Go.
- `Run` returns `CompletedRun` with embedded error info (stderr + exit_code), never panics. This matches the Python/Rust pattern where startup failures are encoded in the result, not thrown.

**Zero-value safety**:

- `Runner` struct fields are function values; nil fields would panic. `NewRunner()` must be called. Do not export a way to construct a zero-value `Runner`.
- `CommandSpec` with nil `Argv` is guarded in `Run`.

## 13. Parity Matrix (vs. existing implementations)

| Feature | Python | Rust | C | TS | Go (planned) |
|---------|--------|------|---|-----|--------------|
| build_prompt_spec | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes |
| Runner.stream | yes | fake | no | yes | yes (real, goroutine) |
| ccc CLI | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes |
| Stdin/CWD/Env | yes | yes | yes | yes | yes |
| Startup failure format | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes |
| CCC_REAL_OPENCODE | yes | yes | yes | no | yes |

**No gaps**: All features from the parity matrix are covered. Go will match the feature set with superior streaming.

## 14. Open Issues / Decisions Needed

- **Module path**: `call-coding-clis/go` is a placeholder. Confirm with repo owner before `go mod init`.
- **Go version floor**: Proposed 1.21. Confirm minimum supported Go version for CI.

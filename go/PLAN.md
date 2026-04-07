# Go Implementation Plan for call-coding-clis

## 1. Module Structure

```
go/
  go.mod                # module github.com/anomalyco/call-coding-clis/go  (TBD)
  ccc.go                # CommandSpec, CompletedRun, Runner, build_prompt_spec
  cmd/
    ccc/
      main.go           # CLI binary entrypoint
  ccc_test.go           # library unit tests
  cmd/
    ccc/
      main_test.go      # CLI integration tests (may stay in ccc_test.go)
```

Single package `ccc` for the library, with `cmd/ccc/` as the CLI binary subdirectory. This keeps the library importable as `ccc` while providing a standard Go `cmd/` layout for the binary.

## 2. Library API — Go Structs

```go
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
- Test injection: `RunWithExecutor(exec func(CommandSpec) CompletedRun) *Runner` and `RunWithStreamExecutor(exec func(CommandSpec, StreamCallback) CompletedRun) *Runner`.

```go
func BuildPromptSpec(prompt string) (CommandSpec, error)
```

- Trims via `strings.TrimSpace`.
- Returns error `"prompt must not be empty"` on empty/whitespace-only input.
- Returns `CommandSpec{Argv: []string{"opencode", "run", trimmed}}`.

## 3. Subprocess via `os/exec`

`Run` path:

1. Construct `exec.Cmd` from `spec.Argv[0]` (program) and `spec.Argv[1:]` (args).
2. Set `cmd.Dir = spec.Cwd` if non-empty.
3. Build environment: copy `os.Environ()`, parse into map, overlay `spec.Env`, set `cmd.Env`.
4. If `spec.StdinText != ""`, set `cmd.Stdin = strings.NewReader(spec.StdinText)`.
5. Call `cmd.CombinedOutput()` or `cmd.Output()` — prefer `cmd.Output()` to keep stdout/stderr separate.
6. On error from `cmd.Start()` (i.e. binary not found / permission denied), return `CompletedRun` with `ExitCode: 1`, `Stderr: fmt.Sprintf("failed to start %s: %s\n", spec.Argv[0], err)`.
7. On successful completion, populate `ExitCode` from `cmd.ProcessState.ExitCode()` (returns -1 for signal; normalize to 1 to match other implementations).

`Stream` path (Go-idiomatic improvement):

1. Use `cmd.StdoutPipe()` and `cmd.StderrPipe()`.
2. Launch two goroutines, each reading from its pipe via `bufio.Scanner` and calling `onEvent("stdout", line)` / `onEvent("stderr", line)` per line.
3. Write stdin in a third goroutine if needed.
4. `cmd.Wait()` in the main goroutine, then `sync.WaitGroup` to ensure all readers complete.
5. Accumulate output for the returned `CompletedRun` (concatenate all lines with newlines).

## 4. `ccc` CLI Binary (`cmd/ccc/main.go`)

```
go build ./cmd/ccc
```

Logic mirrors `python/call_coding_clis/cli.py`:

1. Parse `os.Args[1:]`.
2. If `len(args) != 1`: print `usage: ccc "<Prompt>"` to stderr, `os.Exit(1)`.
3. Call `ccc.BuildPromptSpec(args[0])`. On error, print error to stderr, `os.Exit(1)`.
4. Respect `CCC_REAL_OPENCODE` env var: if set, replace `spec.Argv[0]` with its value.
5. Run `ccc.NewRunner().Run(spec)`.
6. If `result.Stdout != ""`, print to stdout (no trailing newline added — `os.Stdout.WriteString`).
7. If `result.Stderr != ""`, print to stderr.
8. `os.Exit(result.ExitCode)`.

## 5. Prompt Trimming

- `strings.TrimSpace(prompt)` — handles spaces, tabs, newlines, Unicode whitespace.
- Empty check: `trimmed == ""`.
- Return `fmt.Errorf("prompt must not be empty")` — matches all other implementations.

## 6. Error Format: `argv[0]` Only

On subprocess startup failure:
```
failed to start <argv[0]>: <os/exec error message>
```

Use `spec.Argv[0]` only, not the full argv slice. This matches Python, Rust, and C implementations.

## 7. Exit Code Forwarding

- CLI calls `os.Exit(result.ExitCode)` directly.
- No wrapping or post-processing of the exit code.
- For signal-killed processes, `ProcessState.ExitCode()` returns -1 — normalize to 1 to match Rust (`unwrap_or(1)`) and C (`WIFEXITED` guard).

## 8. Test Strategy

**Unit tests** (`ccc_test.go`):

- `TestBuildPromptSpec_Valid` — verify argv is `["opencode", "run", "foo bar"]`.
- `TestBuildPromptSpec_Empty` — verify error returned.
- `TestBuildPromptSpec_WhitespaceOnly` — verify error returned.
- `TestBuildPromptSpec_TrimsWhitespace` — verify leading/trailing spaces removed.
- `TestRunner_NonexistentBinary` — run spec with argv `["__nonexistent_binary_xyz__"]`, assert stderr contains `"failed to start"`, exit_code is 1.

**Executor injection for testing**:

- `RunWithExecutor` accepts a `func(CommandSpec) CompletedRun` to avoid requiring real subprocess execution in unit tests.
- Example: inject an executor that returns a canned `CompletedRun`.

**`CCC_REAL_OPENCODE` env var**:

- In `cmd/ccc/main.go`, check `os.Getenv("CCC_REAL_OPENCODE")` and replace `spec.Argv[0]` if set.
- This allows `tests/test_ccc_contract.py` to point the Go binary at a fake/test opencode.

**Contract tests**:

- Build the `ccc` binary and run the existing `tests/test_ccc_contract.py` against it.
- May require a small shell wrapper or Makefile target: `go build -o go/ccc ./cmd/ccc`.

**Running**:

```sh
go test ./...
CCC_REAL_OPENCODE=/path/to/fake go test ./...
```

## 9. Go-Specific Design Decisions

**Goroutines for streaming**:

The `Stream` method is where Go shines. Use `bufio.Scanner` in two goroutines reading stdout and stderr pipes concurrently. A `sync.WaitGroup` coordinates completion. This is genuinely streaming (line-by-line), unlike the Rust implementation which buffers everything and calls back at the end.

**Implicit interfaces**:

No interface definitions needed for `StreamCallback` — it's just a `func(string, string)`. The executor injection uses function values directly (Go's first-class functions). No `Executor` trait/interface required.

**Error values**:

- `BuildPromptSpec` returns `(CommandSpec, error)` — idiomatic Go.
- `Run` returns `CompletedRun` with embedded error info (stderr + exit_code), never panics. This matches the Python/Rust pattern where startup failures are encoded in the result, not thrown.

**Zero-value friendliness**:

- `CommandSpec` with nil `Argv` should be considered invalid (guard in `Run`).
- `Runner` struct fields are functions; `NewRunner()` must be called (or provide a `Default()` equivalent).

## 10. Parity Gaps (vs. existing implementations)

| Feature | Python | Rust | C | Go (planned) |
|---------|--------|------|---|--------------|
| build_prompt_spec | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes |
| Runner.stream | yes (real) | no (fake) | no | yes (real, goroutine-based) |
| ccc CLI | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes |
| Stdin/CWD/Env | yes | yes | yes | yes |
| Startup failure format | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes |
| CCC_REAL_OPENCODE | yes | yes | yes | yes |
| Streaming (real line-by-line) | yes | no | no | yes |

**Go advantage**: The Go `Stream` implementation will be the only one with true line-by-line streaming (Python uses `Popen` but reads all at once; Rust buffers everything). This is a natural fit for goroutines + piped I/O.

**No gaps**: All features from the parity matrix are covered. The Go implementation will have full parity plus superior streaming.

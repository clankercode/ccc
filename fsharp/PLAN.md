# F# Implementation Plan: call-coding-clis

## 1. Project Structure

```
fsharp/
├── CallCodingClis.sln
├── src/
│   ├── CallCodingClis/
│   │   ├── CallCodingClis.fsproj          # netstandard2.1 library
│   │   ├── CommandSpec.fs                  # CommandSpec, CompletedRun records
│   │   ├── Runner.fs                       # Runner type with run/stream
│   │   ├── PromptSpec.fs                   # build_prompt_spec function
│   │   └── Library.fs                      # module re-exports (InternalApi)
│   └── Ccc.Cli/
│       ├── Ccc.Cli.fsproj                  # net8.0 console app, refs library
│       └── Program.fs                      # ccc CLI entry point
├── tests/
│   ├── CallCodingClis.Tests/
│   │   ├── CallCodingClis.Tests.fsproj
│   │   ├── PromptSpecTests.fs
│   │   ├── RunnerTests.fs
│   │   └── StartupFailureTests.fs
│   └── Ccc.Cli.Tests/
│       ├── Ccc.Cli.Tests.fsproj
│       └── CliContractTests.fs
└── PLAN.md                                 # this file
```

**Solution layout rationale:**
- Single `.sln` with library + CLI + test projects
- Library targets `netstandard2.1` for maximum compatibility
- CLI targets `net8.0` (LTS)
- Tests target `net8.0`, invoke the CLI binary as a subprocess (same pattern as `test_ccc_contract.py`)

## 2. Library API: F# Types

### Records

```fsharp
type CommandSpec = {
    Argv: string list
    StdinText: string option
    Cwd: string option
    Env: Map<string, string>
}

type CompletedRun = {
    Argv: string list
    ExitCode: int
    Stdout: string
    Stderr: string
}
```

### `build_prompt_spec`

```fsharp
let buildPromptSpec (prompt: string) : Result<CommandSpec, string>
```

- Trim via `prompt.Trim()`
- Return `Error "prompt must not be empty"` when trimmed is empty/whitespace-only
- Return `Ok { Argv = ["opencode"; "run"; trimmed]; StdinText = None; Cwd = None; Env = Map.empty }`

Using `Result<CommandSpec, string>` follows F# convention (Rust uses `Result`, Python raises `ValueError`, TS throws). The error message matches the contract: `"prompt must not be empty"`.

### `Runner`

```fsharp
type Runner(executor, streamExecutor) =
    member _.Run(spec: CommandSpec) : CompletedRun
    member _.Stream(spec: CommandSpec, onEvent: string -> string -> unit) : CompletedRun
```

Constructor accepts optional executor functions for testability (same pattern as all other implementations). Defaults to real subprocess execution.

## 3. Subprocess via System.Diagnostics.Process

```fsharp
let private runProcess (spec: CommandSpec) : CompletedRun =
    let psi = ProcessStartInfo()
    psi.FileName <- List.head spec.Argv
    psi.Arguments <- String.Join(" ", spec.Argv |> List.skip 1 |> List.map (fun a -> $"\"{a}\""))
    psi.UseShellExecute <- false
    psi.RedirectStandardOutput <- true
    psi.RedirectStandardError <- true
    psi.RedirectStandardInput <- spec.StdinText.IsSome
    if spec.Cwd.IsSome then psi.WorkingDirectory <- spec.Cwd.Value
    // merge env: start from Environment, overlay spec.Env

    try
        use proc = Process.Start(psi)
        // write stdin if present, then close
        let stdout = proc.StandardOutput.ReadToEnd()
        let stderr = proc.StandardError.ReadToEnd()
        proc.WaitForExit()
        { Argv = spec.Argv; ExitCode = proc.ExitCode; Stdout = stdout; Stderr = stderr }
    with :? System.ComponentModel.Win32Exception as ex ->
        let msg = $"failed to start {List.head spec.Argv}: {ex.Message}\n"
        { Argv = spec.Argv; ExitCode = 1; Stdout = ""; Stderr = msg }
```

Key points:
- `Win32Exception` (or `FileNotFoundException` on some platforms) catches binary-not-found
- `UseShellExecute = false` required for redirect
- `System.Diagnostics.Process` is cross-platform via .NET runtime
- `RedirectStandardInput = true` only when `StdinText` is `Some`
- stdin written synchronously before `WaitForExit()` (sufficient; matches C impl's `communicate` pattern)

**Startup failure handling:** On .NET, `Process.Start` can throw:
- `Win32Exception` — binary not found or permission denied (the common case)
- `FileNotFoundException` — less common but possible on some platforms
- `InvalidOperationException` — already running

We catch broadly (`:? System.ComponentModel.Win32Exception`) and produce the error format `"failed to start <argv[0]>: <message>\n"`, matching other implementations.

## 4. ccc CLI as dotnet console app

`Program.fs` — minimal, follows the exact same pattern as Rust/TS/C CLIs:

```fsharp
[<EntryPoint>]
let main args =
    if args.Length <> 1 then
        eprintfn "usage: ccc \"<Prompt>\""
        1
    else
        match buildPromptSpec args.[0] with
        | Error msg ->
            eprintfn "%s" msg
            1
        | Ok spec ->
            let runner = Runner()
            // For streaming parity with TS, use Stream to forward output in real-time
            let result = runner.Stream(spec, fun channel chunk ->
                match channel with
                | "stdout" -> printf "%s" chunk
                | _ -> eprintf "%s" chunk)
            result.ExitCode
```

**Build/publish:** `dotnet publish -c Release -o publish` produces a self-contained binary. For the contract tests, we use `dotnet run --project src/Ccc.Cli -- <prompt>`.

**CCC_REAL_OPENCODE override:** Check `Environment.GetEnvironmentVariable "CCC_REAL_OPENCODE"` in `buildPromptSpec` or in the CLI directly. If set, use that as the binary name instead of `"opencode"`.

## 5. Prompt Trimming and Empty Rejection

```fsharp
let buildPromptSpec (prompt: string) : Result<CommandSpec, string> =
    let trimmed = prompt.Trim()
    if System.String.IsNullOrEmpty trimmed then
        Error "prompt must not be empty"
    else
        Ok { Argv = ["opencode"; "run"; trimmed]
             StdinText = None; Cwd = None; Env = Map.empty }
```

- `String.Trim()` handles all Unicode whitespace (same as Python's `.strip()`)
- `String.IsNullOrEmpty` catches both empty and whitespace-only-after-trim
- Exact error message `"prompt must not be empty"` matches Python/Rust/TS/C

## 6. Error Format

`"failed to start <argv[0]>: <error-message>\n"`

- Only `argv[0]`, never the full argv list
- Trailing newline included
- Produced in the `runProcess` catch handler

## 7. Exit Code Forwarding

The CLI returns `result.ExitCode` from `main`. Since `main` returns `int`, this naturally becomes the process exit code. For streaming mode that uses `System.Diagnostics.Process` with redirected streams, we call `WaitForExit()` and return `proc.ExitCode`.

## 8. Test Strategy

**Framework:** xUnit — it is the standard .NET test framework with good F# support, broad tooling (VS Code, CI), and matches the project's preference for simplicity.

**Test structure:**

| Test file | What it tests |
|-----------|--------------|
| `PromptSpecTests.fs` | `buildPromptSpec`: valid prompt, empty string, whitespace-only, leading/trailing spaces |
| `RunnerTests.fs` | `Runner.run` with injected executor (mock), `CCC_REAL_OPENCODE` override |
| `StartupFailureTests.fs` | Running with nonexistent binary → stderr contains `"failed to start"` |
| `CliContractTests.fs` | Subprocess tests invoking `dotnet run --project src/Ccc.Cli` matching the 4 contract test scenarios |

**CCC_REAL_OPENCODE override:**
- In `buildPromptSpec`, check the env var. If set, replace `"opencode"` in the argv with its value.
- In tests, set the env var to a stub script path before invoking the CLI.

**Test execution:** `dotnet test` from the `fsharp/` directory runs all test projects.

## 9. F#-Specific Considerations

### Discriminated Unions
- Could model `StreamEvent = Stdout of string | Stderr of string` instead of `(string * string)` callback. Keep the callback as `(string -> string -> unit)` to match the cross-language contract, but internally could use the DU for pattern matching.

### Async Workflows
- `System.Diagnostics.Process` is synchronous by default. For `Stream`, we need real output streaming (not `ReadToEnd` which buffers). Use `Process.BeginOutputReadLine` + `Process.OutputDataReceived` event, or `async { }` with `Async.AwaitEvent`.
- Alternative: use `process.StandardOutput.ReadLine()` in an async loop. Since the library contract allows non-streaming fallback (Rust does this), we can ship v1 with buffered read like Rust's `default_stream_executor`.
- If real streaming is desired, use `Task`-based async with cancellation support.

### Functional Pipeline Style
- Use `|>` and composition. The `buildPromptSpec` and `Runner` functions can be composed naturally.
- No classes needed except `Runner` (which exists in all implementations as the injectable orchestrator).
- Records with `{ Argv = ...; ... }` syntax instead of constructors.

### Namespace / Module Organization
```
namespace CallCodingClis

module CommandSpec = ...
module CompletedRun = ...
module PromptSpec = ...
module Runner = ...
```

Or simpler: single `CallCodingClis` namespace with types and functions at top level.

### No Mutable State
- F# naturally avoids mutation. The `Process` usage requires `use` bindings (IDisposable), which is idiomatic.

### File ordering in fsproj
- F# files must be listed in dependency order in the fsproj (or use `<Compile Include="**/*.fs" />` with careful ordering). Alternatively, use the SDK's default alphabetical ordering by naming files with numeric prefixes: `01_CommandSpec.fs`, `02_CompletedRun.fs`, etc.

## 10. Parity Gaps to Watch For

### Must have (v1)
- [x] `build_prompt_spec` with trim + empty rejection
- [x] `Runner.run` with subprocess execution
- [x] `Runner.stream` (buffered fallback acceptable for v1, matching Rust)
- [x] ccc CLI with single-arg validation
- [x] `CCC_REAL_OPENCODE` env var override
- [x] Startup failure error format: `"failed to start <argv[0]>: ..."`
- [x] Exit code forwarding
- [x] Stdin/CWD/Env support in CommandSpec

### Deferred to v2
- Real-time streaming (true line-by-line output forwarding, not buffered)
- `CCC_RUNNER_PREFIX_JSON` env var support (only TypeScript has this currently)

### Platform concerns
- `ProcessStartInfo.FileName` works with PATH lookup on all platforms
- `Win32Exception` is the standard .NET exception for process startup failures on all platforms
- Argument escaping: `ProcessStartInfo.ArgumentList` (available in .NET Core 2.1+) avoids manual quoting — use this instead of `Arguments` string
- `ProcessStartInfo.ArgumentList` is the preferred approach since it handles escaping correctly

### Integration with existing contract tests
- Add a new `subprocess.run(["dotnet", "run", "--project", "fsharp/src/Ccc.Cli", "--", PROMPT], ...)` block to each of the 4 test methods in `tests/test_ccc_contract.py`
- The test assertions (`assert_equal_output`, `assert_rejects_empty`, etc.) will apply unchanged

### Startup failure platform difference
- On Linux/macOS, `Process.Start` throws `System.ComponentModel.Win32Exception` for ENOENT
- On Linux/macOS with .NET 7+, it may throw `System.IO.FileNotFoundException`
- Catch both to be safe

### ArgumentList vs Arguments
- Use `psi.ArgumentList.AddRange(argv |> List.skip 1)` instead of `psi.Arguments` string
- This avoids shell-injection-style quoting issues and handles paths with spaces correctly
- Available on netstandard2.1+ via .NET Core

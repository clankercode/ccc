# F# Implementation Plan: call-coding-clis

## 1. Project Structure

```
fsharp/
├── CallCodingClis.sln
├── Directory.Build.props              # shared MSBuild properties (target framework, version)
├── src/
│   ├── CallCodingClis/
│   │   ├── CallCodingClis.fsproj      # net6.0 library
│   │   ├── 01_CommandSpec.fs          # CommandSpec record
│   │   ├── 02_CompletedRun.fs         # CompletedRun record
│   │   ├── 03_PromptSpec.fs           # buildPromptSpec function
│   │   ├── 04_ProcessRunner.fs        # default subprocess executor
│   │   ├── 05_Runner.fs               # Runner type (run/stream, injectable)
│   │   └── Library.fs                 # top-level module with public API re-exports
│   └── Ccc.Cli/
│       ├── Ccc.Cli.fsproj             # net6.0 console app, refs library
│       └── Program.fs                 # ccc CLI entry point
├── tests/
│   ├── CallCodingClis.Tests/
│   │   ├── CallCodingClis.Tests.fsproj
│   │   ├── PromptSpecTests.fs
│   │   ├── RunnerTests.fs
│   │   └── StartupFailureTests.fs
│   └── Ccc.Cli.Tests/
│       ├── Ccc.Cli.Tests.fsproj
│       └── CliContractTests.fs
└── PLAN.md                            # this file
```

### Design decisions

- Single `.sln` with library + CLI + test projects.
- **Library and CLI both target `net6.0`** (lowest LTS with `ProcessStartInfo.ArgumentList`).
  `netstandard2.1` does not provide `ArgumentList`; targeting net6.0 avoids
  the manual shell-escaping pitfall entirely.
- Tests target `net6.0`. Library tests inject executors (no subprocess); CLI
  contract tests invoke `dotnet run` as a subprocess.
- Source files use numeric prefixes (`01_`, `02_`, …) so alphabetical
  compilation order satisfies F#'s file-ordering constraint without explicit
  `<Compile>` entries in the fsproj.

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

F# convention uses PascalCase for record fields. The cross-language contract
names these `argv`, `exit_code`, etc.; the mapping is documented here so
readers coming from the contract spec can find the corresponding F# members.

### `buildPromptSpec`

```fsharp
let buildPromptSpec (prompt: string) : Result<CommandSpec, string>
```

- Trim via `prompt.Trim()`
- Return `Error "prompt must not be empty"` when trimmed is empty/whitespace-only
- Return `Ok { Argv = ["opencode"; "run"; trimmed]; StdinText = None; Cwd = None; Env = Map.empty }`
- Uses `Result<CommandSpec, string>` — idiomatic F# (cf. Rust `Result`, Python `ValueError`, TS `Error`)

Note: `CCC_REAL_OPENCODE` is handled **only in the CLI layer** (section 4),
not in the library. This matches the C implementation pattern and keeps the
library free of environment-mutation side effects.

## 3. Subprocess Execution

### Default executor (`ProcessRunner` module)

```fsharp
module ProcessRunner =
    open System.Diagnostics

    let run (spec: CommandSpec) : CompletedRun =
        let psi = ProcessStartInfo()
        psi.FileName <- List.head spec.Argv
        for arg in (spec.Argv |> List.skip 1) do
            psi.ArgumentList.Add arg
        psi.UseShellExecute <- false
        psi.RedirectStandardOutput <- true
        psi.RedirectStandardError <- true
        psi.RedirectStandardInput <- spec.StdinText.IsSome
        if spec.Cwd.IsSome then
            psi.WorkingDirectory <- spec.Cwd.Value

        for kv in spec.Env do
            psi.Environment.[kv.Key] <- kv.Value

        try
            use proc = Process.Start psi
            if spec.StdinText.IsSome then
                proc.StandardInput.Write(spec.StdinText.Value)
                proc.StandardInput.Close()
            let stdout = proc.StandardOutput.ReadToEnd()
            let stderr = proc.StandardError.ReadToEnd()
            proc.WaitForExit()
            { Argv = spec.Argv
              ExitCode = proc.ExitCode
              Stdout = stdout
              Stderr = stderr }
        with
        | :? System.ComponentModel.Win32Exception as ex ->
            { Argv = spec.Argv; ExitCode = 1; Stdout = ""
              Stderr = $"failed to start {List.head spec.Argv}: {ex.Message}\n" }
        | :? System.IO.FileNotFoundException as ex ->
            { Argv = spec.Argv; ExitCode = 1; Stdout = ""
              Stderr = $"failed to start {List.head spec.Argv}: {ex.Message}\n" }
```

Key points:

- `ArgumentList.Add` handles quoting/escaping correctly (no manual `"\"arg\""` hack).
- `psi.Environment.[key] <- value` overlays on the inherited environment — no
  need to copy `Environment.GetEnvironmentVariables` manually.
- Stdin is written synchronously then closed before `ReadToEnd`. This matches
  Rust's `command.output()` (which calls `communicate` internally).
- **Two exception types caught**: `Win32Exception` (ENOENT / permission denied on
  Linux/macOS) and `FileNotFoundException` (possible on .NET 7+). Both produce
  the contract-mandated format `"failed to start <argv[0]>: <message>\n"`.
- `UseShellExecute = false` is required for stream redirection.

### Stream executor (v1: buffered, matching Rust)

```fsharp
let stream (spec: CommandSpec) (onEvent: string -> string -> unit) : CompletedRun =
    let result = run spec
    if not (System.String.IsNullOrEmpty result.Stdout) then
        onEvent "stdout" result.Stdout
    if not (System.String.IsNullOrEmpty result.Stderr) then
        onEvent "stderr" result.Stderr
    result
```

This is identical to Rust's `default_stream_executor`: run to completion, then
fire callbacks. True line-by-line streaming can be added later using
`Process.BeginOutputReadLine` / `OutputDataReceived` events.

## 4. ccc CLI (`Program.fs`)

```fsharp
open System
open CallCodingClis

[<EntryPoint>]
let main args =
    if Array.length args <> 1 then
        eprintfn "usage: ccc \"<Prompt>\""
        1
    else
        let binary =
            match Environment.GetEnvironmentVariable "CCC_REAL_OPENCODE" with
            | null | "" -> "opencode"
            | v -> v

        match buildPromptSpec args.[0] with
        | Error msg ->
            eprintfn "%s" msg
            1
        | Ok spec ->
            let spec =
                { spec with Argv = binary :: (spec.Argv |> List.skip 1) }
            let runner = Runner()
            let result = runner.Stream(spec, fun channel chunk ->
                match channel with
                | "stdout" -> printf "%s" chunk
                | _ -> eprintf "%s" chunk)
            result.ExitCode
```

Notes:
- `CCC_REAL_OPENCODE` is checked in the CLI only, replacing `"opencode"` in the
  argv head. This matches the C implementation (`ccc.c:48-51`).
- `eprintfn` adds a trailing newline, consistent with all other implementations.
- Uses `Runner.Stream` so output is forwarded (even in v1 buffered mode).
- Exit code forwarded directly via `main` return value.

## 5. Runner Type (Injectable)

```fsharp
type Runner(?runExec, ?streamExec) =
    let runExecutor = defaultArg runExec ProcessRunner.run
    let streamExecutor = defaultArg streamExec ProcessRunner.stream

    member _.Run(spec: CommandSpec) : CompletedRun =
        runExecutor spec

    member _.Stream(spec: CommandSpec, onEvent: string -> string -> unit) : CompletedRun =
        streamExecutor spec onEvent
```

- Optional constructor arguments allow test injection (matches all other impls).
- Default values delegate to `ProcessRunner` module functions.

## 6. Library Re-exports (`Library.fs`)

```fsharp
module CallCodingClis

let buildPromptSpec = PromptSpec.buildPromptSpec
type CommandSpec = CommandSpec.CommandSpec
type CompletedRun = CompletedRun.CompletedRun
type Runner = Runner.Runner
```

This is the last file compiled. It provides a single top-level module
`CallCodingClis` so consumers write `open CallCodingClis` and access all public
types/functions without navigating submodules.

## 7. Test Strategy

### Framework

xUnit — standard .NET test framework with first-class F# support via
`xunit` + `FsUnit.Xunit` for idiomatic assertions.

### Test projects

| Test file | What it tests |
|-----------|--------------|
| `PromptSpecTests.fs` | `buildPromptSpec`: valid prompt, empty string, whitespace-only, leading/trailing spaces |
| `RunnerTests.fs` | `Runner.Run` with injected executor, `CCC_REAL_OPENCODE` not exercised (CLI-only) |
| `StartupFailureTests.fs` | Running with nonexistent binary → stderr contains `"failed to start"` |
| `CliContractTests.fs` | Subprocess tests invoking `dotnet run --project src/Ccc.Cli` matching the 4 contract scenarios |

### Key test patterns

```fsharp
// PromptSpecTests.fs — pure unit tests
[<Fact>]
let ``valid prompt produces correct CommandSpec`` () =
    let spec = buildPromptSpec "Fix the tests"
    spec |> should be (equal (Ok { Argv = ["opencode"; "run"; "Fix the tests"]
                                   StdinText = None; Cwd = None; Env = Map.empty }))

[<Fact>]
let ``empty string returns error`` () =
    buildPromptSpec "" |> should equal (Error "prompt must not be empty")

// RunnerTests.fs — injected executor
let mockExecutor (spec: CommandSpec) : CompletedRun =
    { Argv = spec.Argv; ExitCode = 0
      Stdout = "mocked"; Stderr = "" }

[<Fact>]
let ``Runner uses injected executor`` () =
    let runner = Runner(runExec = mockExecutor)
    let result = runner.Run { Argv = ["echo"; "hi"]
                              StdinText = None; Cwd = None; Env = Map.empty }
    result.Stdout |> should equal "mocked"
```

### `CCC_REAL_OPENCODE` testing

Set env var to a stub script path before invoking the CLI subprocess in
`CliContractTests.fs`. The stub script matches `_write_opencode_stub` from
`test_ccc_contract.py`.

## 8. Build Instructions

### Prerequisites

- .NET SDK 6.0+ (LTS)

### Build

```sh
cd fsharp
dotnet build
```

### Run unit tests

```sh
cd fsharp
dotnet test
```

### Run CLI locally

```sh
cd fsharp
dotnet run --project src/Ccc.Cli -- "Fix the failing tests"
```

### Publish self-contained binary

```sh
cd fsharp
dotnet publish src/Ccc.Cli -c Release -o publish
./publish/Ccc.Cli "Fix the failing tests"
```

### Restore / clean

```sh
dotnet restore
dotnet clean
```

## 9. CI Notes

### GitHub Actions

Add a job to the existing CI workflow (or create `fsharp/.github/workflows/ci.yml`):

```yaml
name: fsharp-ci
on:
  push:
    paths: [ 'fsharp/**' ]
  pull_request:
    paths: [ 'fsharp/**' ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '6.0.x'
      - run: dotnet restore fsharp
      - run: dotnet build fsharp --no-restore
      - run: dotnet test fsharp --no-restore --verbosity normal
```

### Cross-language contract tests

The F# CLI must be added to `tests/test_ccc_contract.py` (see section 10).

## 10. Cross-Language Test Registration

Add an F# invocation block to each of the 4 test methods in
`tests/test_ccc_contract.py`, after the existing C block:

```python
# Add to test_cross_language_ccc_happy_path (and similar for the other 3 tests):
self.assert_equal_output(
    subprocess.run(
        ["dotnet", "run", "--project", "fsharp/src/Ccc.Cli", "--", PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Apply the same pattern to:
- `test_cross_language_ccc_rejects_empty_prompt` — pass `""` as prompt
- `test_cross_language_ccc_requires_one_prompt_argument` — omit the prompt arg
- `test_cross_language_ccc_rejects_whitespace_only_prompt` — pass `"   "` as prompt

The existing assertion helpers (`assert_equal_output`, `assert_rejects_empty`,
`assert_rejects_missing_prompt`) apply unchanged.

**Note:** `dotnet run` is slow on first invocation (restore + build). For CI,
consider building the CLI once and invoking the published binary directly:

```python
# Faster CI alternative — publish once, invoke binary:
# In setUp or module scope:
subprocess.run(
    ["dotnet", "publish", "fsharp/src/Ccc.Cli", "-c", "Release", "-o", "fsharp/publish"],
    cwd=ROOT, check=True, capture_output=True,
)
# Then in tests:
subprocess.run([str(ROOT / "fsharp/publish/Ccc.Cli"), PROMPT], ...)
```

## 11. F#-Specific Considerations

### File ordering in fsproj

F# requires source files to be compiled in dependency order. Two approaches:
1. **Numeric prefixes** (chosen here): `01_CommandSpec.fs`, `02_CompletedRun.fs`, … — works with `<Compile Include="**/*.fs" />` glob.
2. **Explicit `<Compile>` entries**: gives full control but verbose.

The SDK-style fsproj should use:
```xml
<ItemGroup>
  <Compile Include="**/*.fs" />
</ItemGroup>
```
This picks up files alphabetically, which the numeric prefixes control.

### No mutable state

F# naturally avoids mutation. The `Process` usage requires `use` bindings
(`IDisposable`), which is idiomatic. No `let mutable` needed.

### Namespace / Module Organization

- Records live in their own files (`CommandSpec.CommandSpec`, `CompletedRun.CompletedRun`).
- Functions live in named modules (`PromptSpec.buildPromptSpec`).
- `Library.fs` provides the final `CallCodingClis` facade.

### Discriminated unions

A `StreamEvent = Stdout of string | Stderr of string` DU could replace the
`(string * string)` callback internally, but the callback signature must stay
as `string -> string -> unit` to match the cross-language contract. This is
noted for v2 if real streaming is implemented.

### Async workflows (deferred)

`System.Diagnostics.Process` is synchronous. True streaming would use
`Process.BeginOutputReadLine` + `OutputDataReceived` events wrapped in
`async { }`. Deferred to v2 — the buffered fallback matches Rust's v1.

## 12. Parity Checklist

### Must have (v1)

- [x] `buildPromptSpec` with trim + empty rejection
- [x] `Runner.Run` with subprocess execution
- [x] `Runner.Stream` (buffered fallback, matching Rust)
- [x] `ccc` CLI with single-arg validation
- [x] `CCC_REAL_OPENCODE` env var override (CLI layer only)
- [x] Startup failure error format: `"failed to start <argv[0]>: <message>\n"`
- [x] Exit code forwarding
- [x] Stdin / CWD / Env support in `CommandSpec`
- [x] Cross-language contract test registration in `test_ccc_contract.py`

### Deferred to v2

- Real-time line-by-line streaming via `BeginOutputReadLine`
- `CCC_RUNNER_PREFIX_JSON` env var support (only TypeScript has this currently)

### Platform notes

- `ProcessStartInfo.FileName` uses PATH lookup on all platforms
- `ProcessStartInfo.ArgumentList` handles escaping correctly on all platforms (Linux, macOS, Windows)
- `Win32Exception` is thrown on all platforms for process startup failures
- `FileNotFoundException` is additionally possible on .NET 7+
- Both are caught in the default executor

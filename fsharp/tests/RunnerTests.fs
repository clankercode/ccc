module RunnerTests

open Xunit
open CallCodingClis

[<Fact>]
let ``buildPromptSpec valid prompt produces correct argv`` () =
    let result = PromptSpec.buildPromptSpec "hello"
    match result with
    | Ok spec ->
        Assert.Equal<string list>(["opencode"; "run"; "hello"], spec.Argv)
        Assert.True(spec.StdinText.IsNone)
        Assert.True(spec.Cwd.IsNone)
        Assert.True(spec.Env.IsEmpty)
    | Error msg -> Assert.Fail($"Expected Ok, got Error: {msg}")

[<Fact>]
let ``buildPromptSpec trims whitespace`` () =
    let result = PromptSpec.buildPromptSpec "  foo  "
    match result with
    | Ok spec -> Assert.Equal<string list>(["opencode"; "run"; "foo"], spec.Argv)
    | Error msg -> Assert.Fail($"Expected Ok, got Error: {msg}")

[<Fact>]
let ``buildPromptSpec rejects empty string`` () =
    let result = PromptSpec.buildPromptSpec ""
    match result with
    | Error msg -> Assert.Contains("empty", msg)
    | Ok _ -> Assert.Fail("Expected Error for empty prompt")

[<Fact>]
let ``buildPromptSpec rejects whitespace-only`` () =
    let result = PromptSpec.buildPromptSpec "   "
    match result with
    | Error msg -> Assert.Contains("empty", msg)
    | Ok _ -> Assert.Fail("Expected Error for whitespace-only prompt")

[<Fact>]
let ``Runner uses injected executor`` () =
    let mockExecutor (spec: CommandSpec) : CompletedRun =
        { Argv = spec.Argv; ExitCode = 0; Stdout = "mocked"; Stderr = "" }
    let runner = Runner(runExec = mockExecutor)
    let spec = { Argv = ["echo"; "hi"]; StdinText = None; Cwd = None; Env = Map.empty }
    let result = runner.Run(spec)
    Assert.Equal("mocked", result.Stdout)
    Assert.Equal(0, result.ExitCode)

[<Fact>]
let ``Runner stream fires callbacks`` () =
    let mockRun (spec: CommandSpec) : CompletedRun =
        { Argv = spec.Argv; ExitCode = 0; Stdout = "out"; Stderr = "err" }
    let mockStream (spec: CommandSpec) (onEvent: string -> string -> unit) : CompletedRun =
        let result = mockRun spec
        onEvent "stdout" result.Stdout
        onEvent "stderr" result.Stderr
        result
    let mutable stdoutReceived = ""
    let mutable stderrReceived = ""
    let runner = Runner(runExec = mockRun, streamExec = mockStream)
    let spec = { Argv = ["test"]; StdinText = None; Cwd = None; Env = Map.empty }
    let result = runner.Stream(spec, fun channel chunk ->
        match channel with
        | "stdout" -> stdoutReceived <- chunk
        | _ -> stderrReceived <- chunk)
    Assert.Equal("out", stdoutReceived)
    Assert.Equal("err", stderrReceived)

[<Fact>]
let ``startup failure has correct format`` () =
    let runner = Runner()
    let spec = { Argv = ["/nonexistent_binary_xyz"]; StdinText = None; Cwd = None; Env = Map.empty }
    let result = runner.Run(spec)
    Assert.Equal(1, result.ExitCode)
    Assert.StartsWith("failed to start /nonexistent_binary_xyz:", result.Stderr)

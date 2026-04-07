namespace CallCodingClis

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

module ProcessRunner =

    open System.Diagnostics

    let run (spec: CommandSpec) : CompletedRun =
        let argv0 = List.head spec.Argv
        let rest = spec.Argv |> List.skip 1
        let psi = ProcessStartInfo()
        psi.FileName <- argv0
        for arg in rest do
            psi.ArgumentList.Add arg
        psi.UseShellExecute <- false
        psi.RedirectStandardOutput <- true
        psi.RedirectStandardError <- true
        psi.RedirectStandardInput <- spec.StdinText.IsSome
        spec.Cwd |> Option.iter (fun d -> psi.WorkingDirectory <- d)
        for kv in spec.Env do
            psi.Environment.[kv.Key] <- kv.Value
        try
            use proc = Process.Start psi
            spec.StdinText |> Option.iter (fun text ->
                proc.StandardInput.Write text
                proc.StandardInput.Close())
            let stdout = proc.StandardOutput.ReadToEnd()
            let stderr = proc.StandardError.ReadToEnd()
            proc.WaitForExit()
            { Argv = spec.Argv
              ExitCode = proc.ExitCode
              Stdout = stdout
              Stderr = stderr }
        with
        | :? System.ComponentModel.Win32Exception as ex ->
            { Argv = spec.Argv
              ExitCode = 1
              Stdout = ""
              Stderr = $"failed to start %s{argv0}: %s{ex.Message}\n" }
        | :? System.IO.FileNotFoundException as ex ->
            { Argv = spec.Argv
              ExitCode = 1
              Stdout = ""
              Stderr = $"failed to start %s{argv0}: %s{ex.Message}\n" }

    let stream (spec: CommandSpec) (onEvent: string -> string -> unit) : CompletedRun =
        let result = run spec
        if not (System.String.IsNullOrEmpty result.Stdout) then
            onEvent "stdout" result.Stdout
        if not (System.String.IsNullOrEmpty result.Stderr) then
            onEvent "stderr" result.Stderr
        result

type Runner(?runExec, ?streamExec) =
    let runExecutor = defaultArg runExec ProcessRunner.run
    let streamExecutor = defaultArg streamExec ProcessRunner.stream

    member _.Run(spec: CommandSpec) : CompletedRun =
        runExecutor spec

    member _.Stream(spec: CommandSpec, onEvent: string -> string -> unit) : CompletedRun =
        streamExecutor spec onEvent

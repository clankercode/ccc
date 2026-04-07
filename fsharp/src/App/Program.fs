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

        match PromptSpec.buildPromptSpec args.[0] with
        | Error msg ->
            eprintfn "%s" msg
            1
        | Ok spec ->
            let spec = { spec with Argv = binary :: (List.skip 1 spec.Argv) }
            let runner = Runner()
            let result = runner.Stream(spec, fun channel chunk ->
                match channel with
                | "stdout" -> printf "%s" chunk
                | _ -> eprintf "%s" chunk)
            result.ExitCode

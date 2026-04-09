open System
open CallCodingClis

[<EntryPoint>]
let main args =
    if Array.length args = 0 then
        Help.printUsage ()
        1
    elif args = [|"--help"|] || args = [|"-h"|] then
        Help.printHelp ()
        0
    else
        let binaryOverride =
            match Environment.GetEnvironmentVariable "CCC_REAL_OPENCODE" with
            | null | "" -> None
            | v -> Some v

        let parsed = Parser.parseArgs args
        let config = Config.loadConfig None

        try
            let argv, env, warnings = Parser.resolveCommand parsed (Some config)
            warnings |> List.iter (fun warning -> eprintfn "%s" warning)
            let argv =
                match binaryOverride with
                | Some b -> b :: (List.skip 1 argv)
                | None -> argv
            let spec = { Argv = argv; StdinText = None; Cwd = None; Env = env }
            let runner = Runner()
            let result = runner.Stream(spec, fun channel chunk ->
                match channel with
                | "stdout" -> printf "%s" chunk; Console.Out.Flush()
                | _ -> eprintf "%s" chunk; Console.Error.Flush())
            result.ExitCode
        with ex ->
            eprintfn "%s" ex.Message
            1

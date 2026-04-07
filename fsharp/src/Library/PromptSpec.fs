namespace CallCodingClis

module PromptSpec =

    let buildPromptSpec (prompt: string) : Result<CommandSpec, string> =
        let trimmed = prompt.Trim()
        if System.String.IsNullOrEmpty trimmed then
            Error "prompt must not be empty"
        else
            Ok { Argv = ["opencode"; "run"; trimmed]
                 StdinText = None
                 Cwd = None
                 Env = Map.empty }

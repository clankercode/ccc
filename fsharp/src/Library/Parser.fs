namespace CallCodingClis

open System.Text.RegularExpressions

type RunnerInfo = {
    Binary: string
    ExtraArgs: string list
    ThinkingFlags: Map<int, string list>
    ProviderFlag: string
    ModelFlag: string
    AgentFlag: string
}

type ParsedArgs = {
    Runner: string option
    Thinking: int option
    Provider: string option
    Model: string option
    Alias: string option
    Prompt: string
}

type AliasDef = {
    Runner: string option
    Thinking: int option
    Provider: string option
    Model: string option
    Agent: string option
}

type CccConfig = {
    DefaultRunner: string
    DefaultProvider: string
    DefaultModel: string
    DefaultThinking: int option
    Aliases: Map<string, AliasDef>
    Abbreviations: Map<string, string>
}

module Parser =

    let runnerRegistry : Map<string, RunnerInfo> =
        let openCodeInfo = {
            Binary = "opencode"
            ExtraArgs = ["run"]
            ThinkingFlags = Map.empty
            ProviderFlag = ""
            ModelFlag = ""
            AgentFlag = "--agent"
        }
        let claudeInfo = {
            Binary = "claude"
            ExtraArgs = []
            ThinkingFlags = Map.ofList [
                0, ["--thinking"; "disabled"]
                1, ["--thinking"; "enabled"; "--effort"; "low"]
                2, ["--thinking"; "enabled"; "--effort"; "medium"]
                3, ["--thinking"; "enabled"; "--effort"; "high"]
                4, ["--thinking"; "enabled"; "--effort"; "max"]
            ]
            ProviderFlag = ""
            ModelFlag = "--model"
            AgentFlag = "--agent"
        }
        let kimiInfo = {
            Binary = "kimi"
            ExtraArgs = []
            ThinkingFlags = Map.ofList [
                0, ["--no-thinking"]
                1, ["--thinking"]
                2, ["--thinking"]
                3, ["--thinking"]
                4, ["--thinking"]
            ]
            ProviderFlag = ""
            ModelFlag = "--model"
            AgentFlag = "--agent"
        }
        let codexInfo = {
            Binary = "codex"
            ExtraArgs = []
            ThinkingFlags = Map.empty
            ProviderFlag = ""
            ModelFlag = "--model"
            AgentFlag = ""
        }
        let roocodeInfo = {
            Binary = "roocode"
            ExtraArgs = []
            ThinkingFlags = Map.empty
            ProviderFlag = ""
            ModelFlag = ""
            AgentFlag = ""
        }
        let crushInfo = {
            Binary = "crush"
            ExtraArgs = []
            ThinkingFlags = Map.empty
            ProviderFlag = ""
            ModelFlag = ""
            AgentFlag = ""
        }
        Map.ofList [
            "opencode", openCodeInfo
            "claude", claudeInfo
            "kimi", kimiInfo
            "codex", codexInfo
            "roocode", roocodeInfo
            "crush", crushInfo
            "oc", openCodeInfo
            "cc", claudeInfo
            "c", codexInfo
            "cx", codexInfo
            "k", kimiInfo
            "rc", roocodeInfo
            "cr", crushInfo
        ]

    let private runnerSelectorRe = Regex(@"^(?:oc|cc|cx|c|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$", RegexOptions.IgnoreCase)
    let private thinkingRe = Regex(@"^\+([0-4])$")
    let private providerModelRe = Regex(@"^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$")
    let private modelRe = Regex(@"^:([a-zA-Z0-9._-]+)$")
    let private aliasRe = Regex(@"^@([a-zA-Z0-9_-]+)$")

    let parseArgs (argv: string array) : ParsedArgs =
        let mutable runner = None
        let mutable thinking = None
        let mutable provider = None
        let mutable model = None
        let mutable aliasName = None
        let positional = ResizeArray<string>()

        for token in argv do
            if runnerSelectorRe.IsMatch(token) && runner.IsNone && positional.Count = 0 then
                runner <- Some(token.ToLower())
            elif thinkingRe.IsMatch(token) && positional.Count = 0 then
                let m = thinkingRe.Match(token)
                thinking <- Some(int m.Groups.[1].Value)
            elif providerModelRe.IsMatch(token) && positional.Count = 0 then
                let m = providerModelRe.Match(token)
                provider <- Some(m.Groups.[1].Value)
                model <- Some(m.Groups.[2].Value)
            elif modelRe.IsMatch(token) && positional.Count = 0 then
                let m = modelRe.Match(token)
                model <- Some(m.Groups.[1].Value)
            elif aliasRe.IsMatch(token) && aliasName.IsNone && positional.Count = 0 then
                let m = aliasRe.Match(token)
                aliasName <- Some(m.Groups.[1].Value)
            else
                positional.Add(token)

        { Runner = runner
          Thinking = thinking
          Provider = provider
          Model = model
          Alias = aliasName
          Prompt = System.String.Join(" ", positional) }

    let private resolveRunnerName (name: string option) (config: CccConfig) : string =
        match name with
        | None -> config.DefaultRunner
        | Some n ->
            match config.Abbreviations.TryFind(n) with
            | Some abbrev -> abbrev
            | None -> n

    let resolveCommand (parsed: ParsedArgs) (config: CccConfig option) : string list * Map<string, string> * string list =
        let config = defaultArg config {
            DefaultRunner = "oc"
            DefaultProvider = ""
            DefaultModel = ""
            DefaultThinking = None
            Aliases = Map.empty
            Abbreviations = Map.empty
        }

        let runnerName = resolveRunnerName parsed.Runner config
        let mutable warnings = []

        let openCodeInfo =
            match runnerRegistry.TryFind("opencode") with
            | Some info -> info
            | None -> {
                Binary = "opencode"
                ExtraArgs = ["run"]
                ThinkingFlags = Map.empty
                ProviderFlag = ""
                ModelFlag = ""
                AgentFlag = "--agent"
            }

        let fallbackInfo =
            match runnerRegistry.TryFind(config.DefaultRunner) with
            | Some info -> info
            | None -> openCodeInfo

        let info =
            match runnerRegistry.TryFind(runnerName) with
            | Some i -> i
            | None -> fallbackInfo

        let mutable effectiveRunnerName = runnerName

        let aliasDef =
            match parsed.Alias with
            | Some a ->
                match config.Aliases.TryFind(a) with
                | Some ad -> Some ad
                | None -> None
            | None -> None

        let info =
            match aliasDef with
            | Some ad ->
                match ad.Runner with
                | Some r when parsed.Runner.IsNone ->
                    let ern = resolveRunnerName (Some r) config
                    effectiveRunnerName <- ern
                    match runnerRegistry.TryFind(ern) with Some i -> i | None -> info
                | _ -> info
            | None -> info

        let argv = ResizeArray<string>()
        argv.Add(info.Binary)
        for a in info.ExtraArgs do argv.Add(a)

        let effectiveThinking =
            match parsed.Thinking with
            | Some t -> Some t
            | None ->
                match aliasDef with
                | Some ad -> ad.Thinking
                | None -> config.DefaultThinking

        match effectiveThinking with
        | Some t ->
            match info.ThinkingFlags.TryFind(t) with
            | Some flags -> for f in flags do argv.Add(f)
            | None -> ()
        | None -> ()

        let effectiveProvider =
            match parsed.Provider with
            | Some p -> Some p
            | None ->
                match aliasDef with
                | Some ad -> ad.Provider
                | None ->
                    if System.String.IsNullOrEmpty(config.DefaultProvider) then None
                    else Some config.DefaultProvider

        let effectiveModel =
            match parsed.Model with
            | Some m -> Some m
            | None ->
                match aliasDef with
                | Some ad -> ad.Model
                | None ->
                    if System.String.IsNullOrEmpty(config.DefaultModel) then None
                    else Some config.DefaultModel

        match effectiveModel with
        | Some m when not (System.String.IsNullOrEmpty(info.ModelFlag)) ->
            argv.Add(info.ModelFlag)
            argv.Add(m)
        | _ -> ()

        let effectiveAgent =
            match parsed.Alias with
            | Some alias ->
                match aliasDef with
                | Some ad when ad.Agent.IsSome && not (System.String.IsNullOrEmpty ad.Agent.Value) ->
                    ad.Agent
                | Some _ ->
                    None
                | None -> Some alias
            | None -> None

        match effectiveAgent with
        | Some agent when not (System.String.IsNullOrEmpty agent) ->
            if not (System.String.IsNullOrEmpty info.AgentFlag) then
                argv.Add(info.AgentFlag)
                argv.Add(agent)
            else
                warnings <- warnings @ [sprintf "warning: runner \"%s\" does not support agents; ignoring @%s" effectiveRunnerName agent]
        | _ -> ()

        let envOverrides = ResizeArray<string * string>()
        match effectiveProvider with
        | Some p -> envOverrides.Add(("CCC_PROVIDER", p))
        | None -> ()

        let prompt = parsed.Prompt.Trim()
        if System.String.IsNullOrEmpty(prompt) then
            failwith "prompt must not be empty"

        argv.Add(prompt)
        List.ofSeq argv, Map.ofSeq envOverrides, warnings

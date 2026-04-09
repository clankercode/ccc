namespace CallCodingClis

module Config =

    open System
    open System.IO

    let defaultConfig : CccConfig = {
        DefaultRunner = "oc"
        DefaultProvider = ""
        DefaultModel = ""
        DefaultThinking = None
        Aliases = Map.empty
        Abbreviations = Map.empty
    }

    let private (|StringValue|IntValue|Other|) (v: string) =
        let v = v.Trim()
        if v.Length >= 2 && v.StartsWith("\"") && v.EndsWith("\"") then
            StringValue(v.[1..v.Length-2])
        else
            match Int32.TryParse(v) with
            | true, n -> IntValue n
            | false, _ -> Other

    let private parseToml (content: string) : Map<string, Map<string, obj>> =
        let sections = ResizeArray<string * ResizeArray<string * obj>>()
        let mutable currentSection = ""
        let mutable currentPairs = ResizeArray<string * obj>()

        for line in content.Split('\n') do
            let line = line.Trim()
            if line.StartsWith("[") && line.EndsWith("]") then
                if currentPairs.Count > 0 then
                    sections.Add(currentSection, currentPairs)
                currentSection <- line.[1..line.Length-2]
                currentPairs <- ResizeArray<string * obj>()
            elif line.Contains("=") then
                let eqIdx = line.IndexOf('=')
                let key = line.[..eqIdx-1].Trim()
                let valueStr = line.[eqIdx+1..]
                match valueStr with
                | StringValue s -> currentPairs.Add(key, box s)
                | IntValue n -> currentPairs.Add(key, box n)
                | Other -> ()

        if currentPairs.Count > 0 then
            sections.Add(currentSection, currentPairs)

        sections
        |> Seq.map (fun (s, pairs) -> s, pairs |> Seq.toList |> Map.ofList)
        |> Map.ofSeq

    let private extractConfig (data: Map<string, Map<string, obj>>) : CccConfig =
        let defaults = match data.TryFind("defaults") with Some d -> d | None -> Map.empty

        let runner =
            match defaults.TryFind("runner") with
            | Some (:? string as v) -> v
            | _ -> defaultConfig.DefaultRunner

        let provider =
            match defaults.TryFind("provider") with
            | Some (:? string as v) -> v
            | _ -> ""

        let model =
            match defaults.TryFind("model") with
            | Some (:? string as v) -> v
            | _ -> ""

        let thinking =
            match defaults.TryFind("thinking") with
            | Some (:? int as v) -> Some v
            | _ -> None

        let abbreviations =
            match data.TryFind("abbreviations") with
            | Some abbr ->
                abbr |> Map.map (fun _ v ->
                    match v with :? string as s -> s | _ -> "")
            | None -> Map.empty

        let aliases =
            data
            |> Map.fold (fun (acc: Map<string, AliasDef>) key (def: Map<string, obj>) ->
                if key.StartsWith("aliases.") then
                    let name = key.[8..]
                    let ad = {
                        Runner = match def.TryFind("runner") with Some(:? string as v) -> Some v | _ -> None
                        Thinking = match def.TryFind("thinking") with Some(:? int as v) -> Some v | _ -> None
                        Provider = match def.TryFind("provider") with Some(:? string as v) -> Some v | _ -> None
                        Model = match def.TryFind("model") with Some(:? string as v) -> Some v | _ -> None
                        Agent = match def.TryFind("agent") with Some(:? string as v) -> Some v | _ -> None
                    }
                    acc.Add(name, ad)
                else
                    acc) Map.empty

        { DefaultRunner = runner
          DefaultProvider = provider
          DefaultModel = model
          DefaultThinking = thinking
          Aliases = aliases
          Abbreviations = abbreviations }

    let private defaultConfigPaths () : string list =
        let paths = ResizeArray<string>()
        let xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME")
        if not (String.IsNullOrEmpty(xdg)) then
            paths.Add(Path.Combine(xdg, "ccc", "config.toml"))
        paths.Add(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config", "ccc", "config.toml"))
        List.ofSeq paths

    let loadConfig (path: string option) : CccConfig =
        let tryLoadFile (p: string) =
            if File.Exists(p) then
                try
                    let content = File.ReadAllText(p)
                    Some(parseToml content |> extractConfig)
                with
                | _ -> None
            else
                None

        match path with
        | Some p ->
            match tryLoadFile p with
            | Some config -> config
            | None -> defaultConfig
        | None ->
            defaultConfigPaths()
            |> List.tryPick tryLoadFile
            |> Option.defaultValue defaultConfig

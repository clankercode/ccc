namespace CallCodingClis

open System
open System.Text.Json

type ToolCall = {
    Id: string
    Name: string
    Arguments: string
}

type ToolResult = {
    ToolCallId: string
    Content: string
    IsError: bool
}

type JsonEvent = {
    EventType: string
    Text: string
    Thinking: string
    ToolCall: ToolCall option
    ToolResult: ToolResult option
}

type ParsedJsonOutput = {
    SchemaName: string
    Events: JsonEvent list
    FinalText: string
    SessionId: string
    Error: string
    CostUsd: float
    DurationMs: int
}

module JsonOutput =

    let private tryGetString (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.String
        then Some (prop.GetString())
        else None

    let private getString el key = tryGetString el key |> Option.defaultValue ""

    let private getBool (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.True then true
        elif el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.False then false
        else false

    let private getFloat (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.Number then
            try prop.GetDouble() with _ -> 0.0
        else 0.0

    let private getInt (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.Number then
            try prop.GetInt32() with _ -> 0
        else 0

    let private tryGetObj (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.Object
        then Some prop
        else None

    let private tryGetArr (el: JsonElement) (key: string) =
        let mutable prop = Unchecked.defaultof<JsonElement>
        if el.TryGetProperty(key, &prop) && prop.ValueKind = JsonValueKind.Array
        then Some prop
        else None

    let private enumerateArr (el: JsonElement) =
        seq { for item in el.EnumerateArray() -> item }

    let private parseLines (rawStdout: string) =
        rawStdout.Trim().Split('\n')
        |> Seq.choose (fun line ->
            let l = line.Trim()
            if String.IsNullOrEmpty l then None
            else
                try Some (JsonDocument.Parse(l))
                with _ -> None)

    let parseOpencodeJson (rawStdout: string) : ParsedJsonOutput =
        let mutable events = []
        let mutable finalText = ""
        let mutable errorText = ""

        for doc in parseLines rawStdout do
            use d = doc
            let root = d.RootElement
            let mutable respProp = Unchecked.defaultof<JsonElement>
            let mutable errProp = Unchecked.defaultof<JsonElement>
            if root.TryGetProperty("response", &respProp) then
                let text = if respProp.ValueKind = JsonValueKind.String then respProp.GetString() else ""
                finalText <- text
                events <- { EventType = "text"; Text = text; Thinking = ""; ToolCall = None; ToolResult = None } :: events
            elif root.TryGetProperty("error", &errProp) then
                let err = if errProp.ValueKind = JsonValueKind.String then errProp.GetString() else ""
                errorText <- err
                events <- { EventType = "error"; Text = err; Thinking = ""; ToolCall = None; ToolResult = None } :: events

        { SchemaName = "opencode"; Events = List.rev events; FinalText = finalText;
          SessionId = ""; Error = errorText; CostUsd = 0.0; DurationMs = 0 }

    let parseClaudeCodeJson (rawStdout: string) : ParsedJsonOutput =
        let mutable events = []
        let mutable finalText = ""
        let mutable sessionId = ""
        let mutable errorText = ""
        let mutable costUsd = 0.0
        let mutable durationMs = 0

        for doc in parseLines rawStdout do
            use d = doc
            let root = d.RootElement
            let msgType = getString root "type"

            if msgType = "system" then
                let sub = getString root "subtype"
                if sub = "init" then sessionId <- getString root "session_id"
                elif sub = "api_retry" then
                    events <- { EventType = "system_retry"; Text = ""; Thinking = ""; ToolCall = None; ToolResult = None } :: events

            elif msgType = "assistant" then
                match tryGetObj root "message" with
                | Some msg ->
                    match tryGetArr msg "content" with
                    | Some content ->
                        let texts =
                            content.EnumerateArray()
                            |> Seq.choose (fun block ->
                                if getString block "type" = "text"
                                then Some (getString block "text")
                                else None)
                            |> Seq.toList
                        if texts.Length > 0 then
                            let text = String.Join("\n", texts)
                            finalText <- text
                            events <- { EventType = "assistant"; Text = text; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                    | None -> ()
                | None -> ()

            elif msgType = "stream_event" then
                match tryGetObj root "event" with
                | Some ev ->
                    let evType = getString ev "type"
                    if evType = "content_block_delta" then
                        match tryGetObj ev "delta" with
                        | Some delta ->
                            let dType = getString delta "type"
                            if dType = "text_delta" then
                                events <- { EventType = "text_delta"; Text = getString delta "text"; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                            elif dType = "thinking_delta" then
                                events <- { EventType = "thinking_delta"; Text = ""; Thinking = getString delta "thinking"; ToolCall = None; ToolResult = None } :: events
                            elif dType = "input_json_delta" then
                                events <- { EventType = "tool_input_delta"; Text = getString delta "partial_json"; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                        | None -> ()
                    elif evType = "content_block_start" then
                        match tryGetObj ev "content_block" with
                        | Some cb ->
                            let cbType = getString cb "type"
                            if cbType = "thinking" then
                                events <- { EventType = "thinking_start"; Text = ""; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                            elif cbType = "tool_use" then
                                let tc = { Id = getString cb "id"; Name = getString cb "name"; Arguments = "" }
                                events <- { EventType = "tool_use_start"; Text = ""; Thinking = ""; ToolCall = Some tc; ToolResult = None } :: events
                        | None -> ()
                | None -> ()

            elif msgType = "tool_use" then
                let tc = { Id = ""; Name = getString root "tool_name"; Arguments = "{}" }
                events <- { EventType = "tool_use"; Text = ""; Thinking = ""; ToolCall = Some tc; ToolResult = None } :: events

            elif msgType = "tool_result" then
                let tr = { ToolCallId = getString root "tool_use_id"; Content = getString root "content"; IsError = getBool root "is_error" }
                events <- { EventType = "tool_result"; Text = ""; Thinking = ""; ToolCall = None; ToolResult = Some tr } :: events

            elif msgType = "result" then
                let sub = getString root "subtype"
                if sub = "success" then
                    let res = getString root "result"
                    if not (String.IsNullOrEmpty res) then finalText <- res
                    costUsd <- getFloat root "cost_usd"
                    durationMs <- getInt root "duration_ms"
                    events <- { EventType = "result"; Text = finalText; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                elif sub = "error" then
                    let err = getString root "error"
                    errorText <- err
                    events <- { EventType = "error"; Text = err; Thinking = ""; ToolCall = None; ToolResult = None } :: events

        { SchemaName = "claude-code"; Events = List.rev events; FinalText = finalText;
          SessionId = sessionId; Error = errorText; CostUsd = costUsd; DurationMs = durationMs }

    let private kimiPassthrough = set [
        "TurnBegin"; "StepBegin"; "StepInterrupted"; "TurnEnd";
        "StatusUpdate"; "HookTriggered"; "HookResolved"; "ApprovalRequest";
        "SubagentEvent"; "ToolCallRequest"
    ]

    let parseKimiJson (rawStdout: string) : ParsedJsonOutput =
        let mutable events = []
        let mutable finalText = ""

        for doc in parseLines rawStdout do
            use d = doc
            let root = d.RootElement
            let wireType = getString root "type"

            if Set.contains wireType kimiPassthrough then
                events <- { EventType = wireType.ToLower(); Text = ""; Thinking = ""; ToolCall = None; ToolResult = None } :: events
            else
                let role = getString root "role"
                if role = "assistant" then
                    let mutable contentProp = Unchecked.defaultof<JsonElement>
                    if root.TryGetProperty("content", &contentProp) then
                        if contentProp.ValueKind = JsonValueKind.String then
                            let text = contentProp.GetString()
                            finalText <- text
                            events <- { EventType = "assistant"; Text = text; Thinking = ""; ToolCall = None; ToolResult = None } :: events
                        elif contentProp.ValueKind = JsonValueKind.Array then
                            let mutable texts = []
                            for part in contentProp.EnumerateArray() do
                                let pt = getString part "type"
                                if pt = "text" then texts <- getString part "text" :: texts
                                elif pt = "think" then
                                    events <- { EventType = "thinking"; Text = ""; Thinking = getString part "think"; ToolCall = None; ToolResult = None } :: events
                            if texts.Length > 0 then
                                let text = String.Join("\n", List.rev texts)
                                finalText <- text
                                events <- { EventType = "assistant"; Text = text; Thinking = ""; ToolCall = None; ToolResult = None } :: events

                    match tryGetArr root "tool_calls" with
                    | Some tcs ->
                        for tcData in tcs.EnumerateArray() do
                            let fnObj = tryGetObj tcData "function"
                            let fnName = match fnObj with Some f -> getString f "name" | None -> ""
                            let fnArgs = match fnObj with Some f -> getString f "arguments" | None -> ""
                            let tc = { Id = getString tcData "id"; Name = fnName; Arguments = fnArgs }
                            events <- { EventType = "tool_call"; Text = ""; Thinking = ""; ToolCall = Some tc; ToolResult = None } :: events
                    | None -> ()

                elif role = "tool" then
                    let mutable texts = []
                    match tryGetArr root "content" with
                    | Some content ->
                        for part in content.EnumerateArray() do
                            if getString part "type" = "text" then
                                let t = getString part "text"
                                if not (t.StartsWith("<system>")) then texts <- t :: texts
                    | None -> ()
                    let tr = { ToolCallId = getString root "tool_call_id"; Content = String.Join("\n", List.rev texts); IsError = false }
                    events <- { EventType = "tool_result"; Text = ""; Thinking = ""; ToolCall = None; ToolResult = Some tr } :: events

        { SchemaName = "kimi"; Events = List.rev events; FinalText = finalText;
          SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }

    let parseJsonOutput (rawStdout: string) (schema: string) : ParsedJsonOutput =
        match schema with
        | "opencode" -> parseOpencodeJson rawStdout
        | "claude-code" -> parseClaudeCodeJson rawStdout
        | "kimi" -> parseKimiJson rawStdout
        | _ -> { SchemaName = schema; Events = []; FinalText = ""; SessionId = "";
                 Error = sprintf "unknown schema: %s" schema; CostUsd = 0.0; DurationMs = 0 }

    let renderParsed (output: ParsedJsonOutput) : string =
        let parts = ResizeArray<string>()
        for ev in output.Events do
            match ev.EventType with
            | "text" | "assistant" | "result" ->
                if not (String.IsNullOrEmpty ev.Text) then parts.Add(ev.Text)
            | "thinking_delta" | "thinking" ->
                if not (String.IsNullOrEmpty ev.Thinking) then parts.Add(sprintf "[thinking] %s" ev.Thinking)
            | "tool_use" ->
                match ev.ToolCall with Some tc -> parts.Add(sprintf "[tool] %s" tc.Name) | None -> ()
            | "tool_result" ->
                match ev.ToolResult with Some tr -> parts.Add(sprintf "[tool_result] %s" tr.Content) | None -> ()
            | "error" ->
                if not (String.IsNullOrEmpty ev.Text) then parts.Add(sprintf "[error] %s" ev.Text)
            | _ -> ()
        if parts.Count > 0 then String.Join("\n", parts)
        else output.FinalText

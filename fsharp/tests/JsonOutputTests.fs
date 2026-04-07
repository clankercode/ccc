module JsonOutputTests

open System
open Xunit
open CallCodingClis

[<Fact>]
let ``parse opencode response`` () =
    let r = JsonOutput.parseOpencodeJson "{\"response\": \"hello\"}\n"
    Assert.Equal(1, r.Events.Length)
    Assert.Equal("text", r.Events.[0].EventType)
    Assert.Equal("hello", r.Events.[0].Text)
    Assert.Equal("hello", r.FinalText)

[<Fact>]
let ``parse opencode error`` () =
    let r = JsonOutput.parseOpencodeJson "{\"error\": \"fail\"}\n"
    Assert.Equal(1, r.Events.Length)
    Assert.Equal("error", r.Events.[0].EventType)
    Assert.Equal("fail", r.Error)

[<Fact>]
let ``parse opencode skips invalid json`` () =
    let r = JsonOutput.parseOpencodeJson "bad\n{\"response\": \"ok\"}\n"
    Assert.Equal(1, r.Events.Length)
    Assert.Equal("ok", r.FinalText)

[<Fact>]
let ``parse claude system init`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\"}\n"
    Assert.Equal("s1", r.SessionId)

[<Fact>]
let ``parse claude assistant`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}\n"
    Assert.Equal(1, r.Events.Length)
    Assert.Equal("assistant", r.Events.[0].EventType)
    Assert.Equal("hi", r.FinalText)

[<Fact>]
let ``parse claude text delta`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"yo\"}}}\n"
    Assert.Equal("text_delta", r.Events.[0].EventType)
    Assert.Equal("yo", r.Events.[0].Text)

[<Fact>]
let ``parse claude tool use`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"tool_use\",\"tool_name\":\"read\",\"tool_input\":{\"a\":1}}\n"
    Assert.Equal("tool_use", r.Events.[0].EventType)
    Assert.Equal("read", r.Events.[0].ToolCall.Value.Name)

[<Fact>]
let ``parse claude tool result`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"out\",\"is_error\":false}\n"
    let tr = r.Events.[0].ToolResult.Value
    Assert.Equal("t1", tr.ToolCallId)
    Assert.Equal("out", tr.Content)
    Assert.False(tr.IsError)

[<Fact>]
let ``parse claude result success`` () =
    let r = JsonOutput.parseClaudeCodeJson "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"done\",\"cost_usd\":0.1,\"duration_ms\":500}\n"
    Assert.Equal("done", r.FinalText)
    Assert.Equal(0.1, r.CostUsd)
    Assert.Equal(500, r.DurationMs)

[<Fact>]
let ``parse kimi assistant text`` () =
    let r = JsonOutput.parseKimiJson "{\"role\":\"assistant\",\"content\":\"hello\"}\n"
    Assert.Equal("assistant", r.Events.[0].EventType)
    Assert.Equal("hello", r.FinalText)

[<Fact>]
let ``parse kimi tool calls`` () =
    let r = JsonOutput.parseKimiJson "{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"1\",\"function\":{\"name\":\"bash\",\"arguments\":\"{}\"}}]}\n"
    let tc = r.Events |> List.find (fun e -> e.EventType = "tool_call")
    Assert.Equal("bash", tc.ToolCall.Value.Name)

[<Fact>]
let ``parse json output dispatches`` () =
    let r = JsonOutput.parseJsonOutput "{\"response\":\"ok\"}\n" "opencode"
    Assert.Equal("opencode", r.SchemaName)
    Assert.Equal("ok", r.FinalText)

[<Fact>]
let ``parse json output unknown schema`` () =
    let r = JsonOutput.parseJsonOutput "" "unknown"
    Assert.True(r.Error.Length > 0)

[<Fact>]
let ``render parsed text events`` () =
    let r = { SchemaName = "test"; Events = [
        { EventType = "text"; Text = "hello"; Thinking = ""; ToolCall = None; ToolResult = None }
        { EventType = "assistant"; Text = "world"; Thinking = ""; ToolCall = None; ToolResult = None }
    ]; FinalText = ""; SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }
    Assert.Equal("hello\nworld", JsonOutput.renderParsed r)

[<Fact>]
let ``render parsed thinking`` () =
    let r = { SchemaName = "test"; Events = [
        { EventType = "thinking"; Text = ""; Thinking = "hmm"; ToolCall = None; ToolResult = None }
    ]; FinalText = ""; SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }
    Assert.Equal("[thinking] hmm", JsonOutput.renderParsed r)

[<Fact>]
let ``render parsed tool and result`` () =
    let r = { SchemaName = "test"; Events = [
        { EventType = "tool_use"; Text = ""; Thinking = ""; ToolCall = Some { Id = ""; Name = "read"; Arguments = "" }; ToolResult = None }
        { EventType = "tool_result"; Text = ""; Thinking = ""; ToolCall = None; ToolResult = Some { ToolCallId = ""; Content = "output"; IsError = false } }
    ]; FinalText = ""; SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }
    Assert.Equal("[tool] read\n[tool_result] output", JsonOutput.renderParsed r)

[<Fact>]
let ``render parsed fallback`` () =
    let r = { SchemaName = "test"; Events = []; FinalText = "fallback"; SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }
    Assert.Equal("fallback", JsonOutput.renderParsed r)

[<Fact>]
let ``render parsed error`` () =
    let r = { SchemaName = "test"; Events = [
        { EventType = "error"; Text = "oops"; Thinking = ""; ToolCall = None; ToolResult = None }
    ]; FinalText = ""; SessionId = ""; Error = ""; CostUsd = 0.0; DurationMs = 0 }
    Assert.Equal("[error] oops", JsonOutput.renderParsed r)

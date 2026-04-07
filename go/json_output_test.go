package ccc

import (
	"testing"
)

func TestParseOpenCodeJson_Response(t *testing.T) {
	raw := `{"response":"hello world"}` + "\n"
	out := ParseOpenCodeJson(raw)
	if out.SchemaName != "opencode" {
		t.Fatalf("schema: %q", out.SchemaName)
	}
	if out.FinalText != "hello world" {
		t.Fatalf("final: %q", out.FinalText)
	}
	if len(out.Events) != 1 || out.Events[0].EventType != "text" {
		t.Fatalf("events: %+v", out.Events)
	}
}

func TestParseOpenCodeJson_Error(t *testing.T) {
	raw := `{"error":"boom"}` + "\n"
	out := ParseOpenCodeJson(raw)
	if out.Error != "boom" {
		t.Fatalf("error: %q", out.Error)
	}
	if len(out.Events) != 1 || out.Events[0].EventType != "error" {
		t.Fatalf("events: %+v", out.Events)
	}
}

func TestParseOpenCodeJson_MixedLines(t *testing.T) {
	raw := `{"response":"hi"}` + "\n" + `{"response":"bye"}` + "\n"
	out := ParseOpenCodeJson(raw)
	if out.FinalText != "bye" {
		t.Fatalf("final: %q", out.FinalText)
	}
	if len(out.Events) != 2 {
		t.Fatalf("events: %d", len(out.Events))
	}
}

func TestParseOpenCodeJson_SkipsInvalidJSON(t *testing.T) {
	raw := "not json\n" + `{"response":"ok"}` + "\n"
	out := ParseOpenCodeJson(raw)
	if out.FinalText != "ok" {
		t.Fatalf("final: %q", out.FinalText)
	}
	if len(out.RawLines) != 1 {
		t.Fatalf("raw_lines: %d", len(out.RawLines))
	}
}

func TestParseClaudeCodeJson_Init(t *testing.T) {
	raw := `{"type":"system","subtype":"init","session_id":"sess123"}` + "\n"
	out := ParseClaudeCodeJson(raw)
	if out.SessionID != "sess123" {
		t.Fatalf("session: %q", out.SessionID)
	}
}

func TestParseClaudeCodeJson_Assistant(t *testing.T) {
	raw := `{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}],"usage":{"input_tokens":10,"output_tokens":5}}}` + "\n"
	out := ParseClaudeCodeJson(raw)
	if out.FinalText != "hello" {
		t.Fatalf("final: %q", out.FinalText)
	}
	if out.Usage["input_tokens"] != 10 {
		t.Fatalf("usage: %+v", out.Usage)
	}
	if len(out.Events) != 1 || out.Events[0].EventType != "assistant" {
		t.Fatalf("events: %+v", out.Events)
	}
}

func TestParseClaudeCodeJson_ToolUse(t *testing.T) {
	raw := `{"type":"tool_use","tool_name":"read","tool_input":{"path":"/tmp/x"}}` + "\n"
	out := ParseClaudeCodeJson(raw)
	if len(out.Events) != 1 {
		t.Fatalf("events: %d", len(out.Events))
	}
	ev := out.Events[0]
	if ev.EventType != "tool_use" || ev.ToolCall == nil {
		t.Fatalf("bad event: %+v", ev)
	}
	if ev.ToolCall.Name != "read" {
		t.Fatalf("tool name: %q", ev.ToolCall.Name)
	}
	if ev.ToolCall.Arguments != `{"path":"/tmp/x"}` {
		t.Fatalf("tool args: %q", ev.ToolCall.Arguments)
	}
}

func TestParseClaudeCodeJson_ToolResult(t *testing.T) {
	raw := `{"type":"tool_result","tool_use_id":"tc1","content":"file contents","is_error":false}` + "\n"
	out := ParseClaudeCodeJson(raw)
	ev := out.Events[0]
	if ev.EventType != "tool_result" || ev.ToolResult == nil {
		t.Fatalf("bad event: %+v", ev)
	}
	if ev.ToolResult.ToolCallID != "tc1" || ev.ToolResult.Content != "file contents" {
		t.Fatalf("tool_result: %+v", ev.ToolResult)
	}
}

func TestParseClaudeCodeJson_ResultSuccess(t *testing.T) {
	raw := `{"type":"result","subtype":"success","result":"done","cost_usd":0.05,"duration_ms":1200}` + "\n"
	out := ParseClaudeCodeJson(raw)
	if out.FinalText != "done" {
		t.Fatalf("final: %q", out.FinalText)
	}
	if out.CostUSD != 0.05 {
		t.Fatalf("cost: %f", out.CostUSD)
	}
	if out.DurationMs != 1200 {
		t.Fatalf("duration: %d", out.DurationMs)
	}
}

func TestParseClaudeCodeJson_ResultError(t *testing.T) {
	raw := `{"type":"result","subtype":"error","error":"fail"}` + "\n"
	out := ParseClaudeCodeJson(raw)
	if out.Error != "fail" {
		t.Fatalf("error: %q", out.Error)
	}
	if len(out.Events) != 1 || out.Events[0].EventType != "error" {
		t.Fatalf("events: %+v", out.Events)
	}
}

func TestParseClaudeCodeJson_ThinkingDelta(t *testing.T) {
	raw := `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}}` + "\n"
	out := ParseClaudeCodeJson(raw)
	ev := out.Events[0]
	if ev.EventType != "thinking_delta" || ev.Thinking != "hmm" {
		t.Fatalf("event: %+v", ev)
	}
}

func TestParseKimiJson_AssistantString(t *testing.T) {
	raw := `{"role":"assistant","content":"hi there"}` + "\n"
	out := ParseKimiJson(raw)
	if out.FinalText != "hi there" {
		t.Fatalf("final: %q", out.FinalText)
	}
}

func TestParseKimiJson_AssistantContentList(t *testing.T) {
	raw := `{"role":"assistant","content":[{"type":"text","text":"hello"},{"type":"think","think":"pondering"},{"type":"text","text":"world"}]}` + "\n"
	out := ParseKimiJson(raw)
	if out.FinalText != "hello\nworld" {
		t.Fatalf("final: %q", out.FinalText)
	}
	var thinkFound bool
	for _, ev := range out.Events {
		if ev.EventType == "thinking" {
			thinkFound = true
			if ev.Thinking != "pondering" {
				t.Fatalf("thinking: %q", ev.Thinking)
			}
		}
	}
	if !thinkFound {
		t.Fatal("no thinking event found")
	}
}

func TestParseKimiJson_ToolCall(t *testing.T) {
	raw := `{"role":"assistant","content":"","tool_calls":[{"id":"tc1","function":{"name":"bash","arguments":"{\"cmd\":\"ls\"}"}}]}` + "\n"
	out := ParseKimiJson(raw)
	if len(out.Events) != 2 {
		t.Fatalf("events: %d", len(out.Events))
	}
	ev := out.Events[1]
	if ev.EventType != "tool_call" || ev.ToolCall == nil {
		t.Fatalf("event: %+v", ev)
	}
	if ev.ToolCall.Name != "bash" || ev.ToolCall.Arguments != `{"cmd":"ls"}` {
		t.Fatalf("tool_call: %+v", ev.ToolCall)
	}
}

func TestParseKimiJson_ToolResult(t *testing.T) {
	raw := `{"role":"tool","tool_call_id":"tc1","content":[{"type":"text","text":"output line"},{"type":"text","text":"<system>hidden</system>"}]}` + "\n"
	out := ParseKimiJson(raw)
	ev := out.Events[0]
	if ev.EventType != "tool_result" || ev.ToolResult == nil {
		t.Fatalf("event: %+v", ev)
	}
	if ev.ToolResult.Content != "output line" {
		t.Fatalf("content: %q", ev.ToolResult.Content)
	}
	if ev.ToolResult.ToolCallID != "tc1" {
		t.Fatalf("tool_call_id: %q", ev.ToolResult.ToolCallID)
	}
}

func TestParseKimiJson_PassthroughEvents(t *testing.T) {
	raw := `{"type":"TurnBegin"}` + "\n" + `{"type":"StepBegin"}` + "\n" + `{"type":"StatusUpdate"}` + "\n"
	out := ParseKimiJson(raw)
	if len(out.Events) != 3 {
		t.Fatalf("events: %d", len(out.Events))
	}
	if out.Events[0].EventType != "turnbegin" {
		t.Fatalf("type[0]: %q", out.Events[0].EventType)
	}
	if out.Events[1].EventType != "stepbegin" {
		t.Fatalf("type[1]: %q", out.Events[1].EventType)
	}
	if out.Events[2].EventType != "statusupdate" {
		t.Fatalf("type[2]: %q", out.Events[2].EventType)
	}
}

func TestParseJsonOutput_Dispatch(t *testing.T) {
	out := ParseJsonOutput(`{"response":"hi"}`+"\n", "opencode")
	if out.SchemaName != "opencode" || out.FinalText != "hi" {
		t.Fatalf("bad dispatch: %+v", out)
	}
}

func TestParseJsonOutput_UnknownSchema(t *testing.T) {
	out := ParseJsonOutput("", "unknown")
	if out.Error == "" {
		t.Fatal("expected error for unknown schema")
	}
}

func TestRenderParsed_Text(t *testing.T) {
	out := ParsedJsonOutput{
		FinalText: "final",
		Events: []JsonEvent{
			{EventType: "assistant", Text: "hello"},
			{EventType: "assistant", Text: "world"},
		},
	}
	s := RenderParsed(out)
	if s != "hello\nworld" {
		t.Fatalf("rendered: %q", s)
	}
}

func TestRenderParsed_ToolUseAndResult(t *testing.T) {
	out := ParsedJsonOutput{
		Events: []JsonEvent{
			{EventType: "tool_use", ToolCall: &ToolCall{Name: "bash"}},
			{EventType: "tool_result", ToolResult: &ToolResult{Content: "ok"}},
		},
	}
	s := RenderParsed(out)
	if s != "[tool] bash\n[tool_result] ok" {
		t.Fatalf("rendered: %q", s)
	}
}

func TestRenderParsed_Thinking(t *testing.T) {
	out := ParsedJsonOutput{
		Events: []JsonEvent{
			{EventType: "thinking_delta", Thinking: "deep thoughts"},
		},
	}
	s := RenderParsed(out)
	if s != "[thinking] deep thoughts" {
		t.Fatalf("rendered: %q", s)
	}
}

func TestRenderParsed_EmptyFallsBackToFinalText(t *testing.T) {
	out := ParsedJsonOutput{FinalText: "fallback"}
	s := RenderParsed(out)
	if s != "fallback" {
		t.Fatalf("rendered: %q", s)
	}
}

func TestRenderParsed_Error(t *testing.T) {
	out := ParsedJsonOutput{
		Events: []JsonEvent{
			{EventType: "error", Text: "something broke"},
		},
	}
	s := RenderParsed(out)
	if s != "[error] something broke" {
		t.Fatalf("rendered: %q", s)
	}
}

require "spec"
require "../src/call_coding_clis/json_output"

describe "parse_opencode_json" do
  it "parses a response line" do
    result = parse_opencode_json(%q({"response": "hello world"}))
    result.schema_name.should eq("opencode")
    result.final_text.should eq("hello world")
    result.events.size.should eq(1)
    result.events[0].event_type.should eq("text")
    result.events[0].text.should eq("hello world")
  end

  it "parses an error line" do
    result = parse_opencode_json(%q({"error": "something went wrong"}))
    result.error.should eq("something went wrong")
    result.events.size.should eq(1)
    result.events[0].event_type.should eq("error")
  end

  it "skips invalid JSON lines" do
    result = parse_opencode_json("not json\n{\"response\": \"ok\"}")
    result.events.size.should eq(1)
    result.final_text.should eq("ok")
  end

  it "handles multiple lines with last response winning" do
    input = "{\"response\": \"first\"}\n{\"response\": \"second\"}"
    result = parse_opencode_json(input)
    result.final_text.should eq("second")
    result.events.size.should eq(2)
  end

  it "handles empty input" do
    result = parse_opencode_json("")
    result.events.should be_empty
  end
end

describe "parse_claude_code_json" do
  it "parses system init" do
    result = parse_claude_code_json(%q({"type": "system", "subtype": "init", "session_id": "abc123"}))
    result.session_id.should eq("abc123")
  end

  it "parses assistant message with text blocks" do
    result = parse_claude_code_json(%q({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}], "usage": {"input_tokens": 10}}}))
    result.final_text.should eq("hello")
    result.events.size.should eq(1)
    result.events[0].event_type.should eq("assistant")
  end

  it "parses stream text_delta" do
    result = parse_claude_code_json(%q({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "hi"}}}))
    result.events.size.should eq(1)
    result.events[0].event_type.should eq("text_delta")
    result.events[0].text.should eq("hi")
  end

  it "parses stream thinking_delta" do
    result = parse_claude_code_json(%q({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": "hmm"}}}))
    result.events[0].event_type.should eq("thinking_delta")
    result.events[0].thinking.should eq("hmm")
  end

  it "parses tool_use" do
    result = parse_claude_code_json(%q({"type": "tool_use", "tool_name": "read_file", "tool_input": {"path": "/foo"}}))
    result.events[0].event_type.should eq("tool_use")
    result.events[0].tool_call.should_not be_nil
    result.events[0].tool_call.not_nil!.name.should eq("read_file")
  end

  it "parses tool_result" do
    result = parse_claude_code_json(%q({"type": "tool_result", "tool_use_id": "tu1", "content": "file contents", "is_error": false}))
    result.events[0].event_type.should eq("tool_result")
    tr = result.events[0].tool_result.not_nil!
    tr.tool_call_id.should eq("tu1")
    tr.content.should eq("file contents")
    tr.is_error.should be_false
  end

  it "parses result success" do
    result = parse_claude_code_json(%q({"type": "result", "subtype": "success", "result": "done", "cost_usd": 0.05, "duration_ms": 1200}))
    result.final_text.should eq("done")
    result.cost_usd.should eq(0.05)
    result.duration_ms.should eq(1200)
    result.events[0].event_type.should eq("result")
  end

  it "parses result error" do
    result = parse_claude_code_json(%q({"type": "result", "subtype": "error", "error": "fail"}))
    result.error.should eq("fail")
    result.events[0].event_type.should eq("error")
  end

  it "parses tool_use_start from stream_event" do
    result = parse_claude_code_json(%q({"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "id": "tc1", "name": "bash"}}}))
    result.events[0].event_type.should eq("tool_use_start")
    result.events[0].tool_call.not_nil!.name.should eq("bash")
  end
end

describe "parse_kimi_json" do
  it "parses passthrough TurnBegin" do
    result = parse_kimi_json(%q({"type": "TurnBegin"}))
    result.events[0].event_type.should eq("turnbegin")
  end

  it "parses assistant with string content" do
    result = parse_kimi_json(%q({"role": "assistant", "content": "hello there"}))
    result.final_text.should eq("hello there")
    result.events[0].event_type.should eq("assistant")
  end

  it "parses assistant with array content containing text and think" do
    json_line = %q({"role": "assistant", "content": [{"type": "text", "text": "result"}, {"type": "think", "think": "reasoning"}]})
    result = parse_kimi_json(json_line)
    result.events.size.should eq(2)
    result.events[0].event_type.should eq("thinking")
    result.events[0].thinking.should eq("reasoning")
    result.events[1].event_type.should eq("assistant")
  end

  it "parses tool calls" do
    json_line = %q({"role": "assistant", "content": "", "tool_calls": [{"id": "tc1", "function": {"name": "edit", "arguments": "{\"file\": \"a\"}"}}]})
    result = parse_kimi_json(json_line)
    tc_event = result.events.find { |e| e.event_type == "tool_call" }.not_nil!
    tc_event.tool_call.not_nil!.name.should eq("edit")
    tc_event.tool_call.not_nil!.arguments.should eq(%q({"file": "a"}))
  end

  it "parses tool result filtering system tags" do
    json_line = %q({"role": "tool", "tool_call_id": "tc1", "content": [{"type": "text", "text": "<system>internal</system>"}, {"type": "text", "text": "visible output"}]})
    result = parse_kimi_json(json_line)
    tr = result.events[0].tool_result.not_nil!
    tr.content.should eq("visible output")
    tr.tool_call_id.should eq("tc1")
  end
end

describe "parse_json_output" do
  it "dispatches to opencode" do
    result = parse_json_output(%q({"response": "hi"}), "opencode")
    result.schema_name.should eq("opencode")
    result.final_text.should eq("hi")
  end

  it "dispatches to claude-code" do
    result = parse_json_output(%q({"type": "system", "subtype": "init", "session_id": "s1"}), "claude-code")
    result.schema_name.should eq("claude-code")
    result.session_id.should eq("s1")
  end

  it "returns error for unknown schema" do
    result = parse_json_output("", "unknown")
    result.error.should contain("unknown schema")
  end
end

describe "render_parsed" do
  it "renders text events" do
    output = ParsedJsonOutput.new(
      schema_name: "opencode",
      events: [JsonEvent.new(event_type: "text", text: "hello")],
      final_text: "hello"
    )
    render_parsed(output).should eq("hello")
  end

  it "renders thinking events" do
    output = ParsedJsonOutput.new(
      schema_name: "test",
      events: [JsonEvent.new(event_type: "thinking", thinking: "deep thoughts")]
    )
    render_parsed(output).should eq("[thinking] deep thoughts")
  end

  it "renders tool use events" do
    output = ParsedJsonOutput.new(
      schema_name: "test",
      events: [JsonEvent.new(event_type: "tool_use", tool_call: ToolCall.new(name: "bash"))]
    )
    render_parsed(output).should eq("[tool] bash")
  end

  it "renders error events" do
    output = ParsedJsonOutput.new(
      schema_name: "test",
      events: [JsonEvent.new(event_type: "error", text: "oops")]
    )
    render_parsed(output).should eq("[error] oops")
  end

  it "falls back to final_text when no renderable events" do
    output = ParsedJsonOutput.new(
      schema_name: "test",
      events: [JsonEvent.new(event_type: "system_retry")],
      final_text: "fallback"
    )
    render_parsed(output).should eq("fallback")
  end

  it "renders tool_result events" do
    output = ParsedJsonOutput.new(
      schema_name: "test",
      events: [JsonEvent.new(event_type: "tool_result", tool_result: ToolResult.new(content: "file data"))]
    )
    render_parsed(output).should eq("[tool_result] file data")
  end
end

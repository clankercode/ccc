import std/[unittest, json, options, strutils]
import call_coding_clis/json_output

suite "parseOpencodeJson":
  test "parses response line":
    let r = parseOpencodeJson("""{"response": "hello world"}""")
    check r.schemaName == "opencode"
    check r.finalText == "hello world"
    check r.events.len == 1
    check r.events[0].eventType == "text"
    check r.events[0].text == "hello world"

  test "parses error line":
    let r = parseOpencodeJson("""{"error": "something went wrong"}""")
    check r.error == "something went wrong"
    check r.events.len == 1
    check r.events[0].eventType == "error"

  test "skips invalid JSON lines":
    let r = parseOpencodeJson("not json\n{\"response\": \"ok\"}")
    check r.events.len == 1
    check r.finalText == "ok"

  test "handles multiple lines":
    let input = """{"response": "first"}""" & "\n" & """{"response": "second"}"""
    let r = parseOpencodeJson(input)
    check r.finalText == "second"
    check r.events.len == 2

  test "handles empty input":
    let r = parseOpencodeJson("")
    check r.events.len == 0

suite "parseClaudeCodeJson":
  test "parses system init":
    let r = parseClaudeCodeJson("""{"type": "system", "subtype": "init", "session_id": "abc123"}""")
    check r.sessionId == "abc123"

  test "parses assistant message":
    let r = parseClaudeCodeJson("""{"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}], "usage": {"input_tokens": 10}}}""")
    check r.finalText == "hello"
    check r.events.len == 1
    check r.events[0].eventType == "assistant"

  test "parses stream text_delta":
    let r = parseClaudeCodeJson("""{"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "hi"}}}""")
    check r.events[0].eventType == "text_delta"
    check r.events[0].text == "hi"

  test "parses stream thinking_delta":
    let r = parseClaudeCodeJson("""{"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": "hmm"}}}""")
    check r.events[0].eventType == "thinking_delta"
    check r.events[0].thinking == "hmm"

  test "parses tool_use":
    let r = parseClaudeCodeJson("""{"type": "tool_use", "tool_name": "read_file", "tool_input": {"path": "/foo"}}""")
    check r.events[0].eventType == "tool_use"
    check r.events[0].toolCall.isSome
    check r.events[0].toolCall.get().name == "read_file"

  test "parses tool_result":
    let r = parseClaudeCodeJson("""{"type": "tool_result", "tool_use_id": "tu1", "content": "file contents", "is_error": false}""")
    check r.events[0].eventType == "tool_result"
    let tr = r.events[0].toolResult.get()
    check tr.toolCallId == "tu1"
    check tr.content == "file contents"
    check tr.isError == false

  test "parses result success":
    let r = parseClaudeCodeJson("""{"type": "result", "subtype": "success", "result": "done", "cost_usd": 0.05, "duration_ms": 1200}""")
    check r.finalText == "done"
    check r.costUsd == 0.05
    check r.durationMs == 1200

  test "parses result error":
    let r = parseClaudeCodeJson("""{"type": "result", "subtype": "error", "error": "fail"}""")
    check r.error == "fail"

  test "parses tool_use_start from stream_event":
    let r = parseClaudeCodeJson("""{"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "id": "tc1", "name": "bash"}}}""")
    check r.events[0].eventType == "tool_use_start"
    check r.events[0].toolCall.get().name == "bash"

suite "parseKimiJson":
  test "parses passthrough TurnBegin":
    let r = parseKimiJson("""{"type": "TurnBegin"}""")
    check r.events[0].eventType == "turnbegin"

  test "parses assistant with string content":
    let r = parseKimiJson("""{"role": "assistant", "content": "hello there"}""")
    check r.finalText == "hello there"
    check r.events[0].eventType == "assistant"

  test "parses assistant with array content":
    let r = parseKimiJson("""{"role": "assistant", "content": [{"type": "text", "text": "result"}, {"type": "think", "think": "reasoning"}]}""")
    check r.events.len == 2
    check r.events[0].eventType == "thinking"
    check r.events[0].thinking == "reasoning"
    check r.events[1].eventType == "assistant"

  test "parses tool calls":
    let r = parseKimiJson("""{"role": "assistant", "content": "", "tool_calls": [{"id": "tc1", "function": {"name": "edit", "arguments": "{}"}}]}""")
    var tcEv: seq[JsonEvent] = @[]
    for ev in r.events:
      if ev.eventType == "tool_call": tcEv.add(ev)
    check tcEv.len == 1
    check tcEv[0].toolCall.get().name == "edit"

  test "parses tool result filtering system tags":
    let r = parseKimiJson("""{"role": "tool", "tool_call_id": "tc1", "content": [{"type": "text", "text": "<system>internal</system>"}, {"type": "text", "text": "visible output"}]}""")
    let tr = r.events[0].toolResult.get()
    check tr.content == "visible output"
    check tr.toolCallId == "tc1"

suite "parseJsonOutput":
  test "dispatches to opencode":
    let r = parseJsonOutput("""{"response": "hi"}""", "opencode")
    check r.schemaName == "opencode"
    check r.finalText == "hi"

  test "dispatches to claude-code":
    let r = parseJsonOutput("""{"type": "system", "subtype": "init", "session_id": "s1"}""", "claude-code")
    check r.sessionId == "s1"

  test "returns error for unknown schema":
    let r = parseJsonOutput("", "unknown")
    doAssert r.error.find("unknown schema") >= 0

suite "renderParsed":
  test "renders text events":
    let output = ParsedJsonOutput(
      schemaName: "opencode",
      events: @[newJsonEvent("text", text = "hello")],
      finalText: "hello"
    )
    check renderParsed(output) == "hello"

  test "renders thinking events":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[newJsonEvent("thinking", thinking = "deep thoughts")]
    )
    check renderParsed(output) == "[thinking] deep thoughts"

  test "renders tool use events":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[newJsonEvent("tool_use", toolCall = some(newToolCall(name = "bash")))]
    )
    check renderParsed(output) == "[tool] bash"

  test "renders error events":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[newJsonEvent("error", text = "oops")]
    )
    check renderParsed(output) == "[error] oops"

  test "falls back to final_text":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[newJsonEvent("system_retry")],
      finalText: "fallback"
    )
    check renderParsed(output) == "fallback"

  test "renders tool_result events":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[newJsonEvent("tool_result", toolResult = some(newToolResult(content = "file data")))]
    )
    check renderParsed(output) == "[tool_result] file data"

  test "renders multiple events with newlines":
    let output = ParsedJsonOutput(
      schemaName: "test",
      events: @[
        newJsonEvent("text", text = "hello"),
        newJsonEvent("tool_use", toolCall = some(newToolCall(name = "bash")))
      ]
    )
    check renderParsed(output) == "hello\n[tool] bash"

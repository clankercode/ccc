defmodule CallCodingClis.JsonOutputTest do
  use ExUnit.Case

  alias CallCodingClis.JsonOutput

  alias CallCodingClis.JsonOutput.{
    ToolCall,
    ToolResult,
    JsonEvent,
    ParsedJsonOutput
  }

  @fixtures Path.expand("../../../tests/fixtures/runner-transcripts", __DIR__)

  describe "parse_opencode_json/1" do
    test "parses a response line" do
      result = JsonOutput.parse_opencode_json(~s({"response": "hello world"}))
      assert result.schema_name == "opencode"
      assert result.final_text == "hello world"
      assert length(result.events) == 1
      assert hd(result.events).event_type == "text"
    end

    test "parses an error line" do
      result = JsonOutput.parse_opencode_json(~s({"error": "something went wrong"}))
      assert result.error == "something went wrong"
      assert hd(result.events).event_type == "error"
    end

    test "skips invalid JSON lines" do
      result = JsonOutput.parse_opencode_json("not json\n{\"response\": \"ok\"}")
      assert length(result.events) == 1
      assert result.final_text == "ok"
    end

    test "handles multiple lines with last response winning" do
      result = JsonOutput.parse_opencode_json(~s({"response": "first"}\n{"response": "second"}))
      assert result.final_text == "second"
      assert length(result.events) == 2
    end

    test "handles empty input" do
      result = JsonOutput.parse_opencode_json("")
      assert result.events == []
    end
  end

  describe "parse_claude_code_json/1" do
    test "parses system init" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "system", "subtype": "init", "session_id": "abc123"})
        )

      assert result.session_id == "abc123"
    end

    test "parses assistant message with text blocks" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "assistant", "message": {"content": [{"type": "text", "text": "hello"}], "usage": {"input_tokens": 10}}})
        )

      assert result.final_text == "hello"
      assert hd(result.events).event_type == "assistant"
    end

    test "parses stream text_delta" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "hi"}}})
        )

      assert hd(result.events).event_type == "text_delta"
      assert hd(result.events).text == "hi"
    end

    test "parses stream thinking_delta" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "thinking_delta", "thinking": "hmm"}}})
        )

      assert hd(result.events).event_type == "thinking_delta"
      assert hd(result.events).thinking == "hmm"
    end

    test "parses tool_use" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "tool_use", "tool_name": "read_file", "tool_input": {"path": "/foo"}})
        )

      assert hd(result.events).event_type == "tool_use"
      assert hd(result.events).tool_call.name == "read_file"
    end

    test "parses tool_result" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "tool_result", "tool_use_id": "tu1", "content": "file contents", "is_error": false})
        )

      assert hd(result.events).event_type == "tool_result"
      tr = hd(result.events).tool_result
      assert tr.tool_call_id == "tu1"
      assert tr.content == "file contents"
      assert tr.is_error == false
    end

    test "parses result success" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "result", "subtype": "success", "result": "done", "cost_usd": 0.05, "duration_ms": 1200})
        )

      assert result.final_text == "done"
      assert result.cost_usd == 0.05
      assert result.duration_ms == 1200
    end

    test "parses result error" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "result", "subtype": "error", "error": "fail"})
        )

      assert result.error == "fail"
    end

    test "parses tool_use_start from stream_event" do
      result =
        JsonOutput.parse_claude_code_json(
          ~s({"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "id": "tc1", "name": "bash"}}})
        )

      assert hd(result.events).event_type == "tool_use_start"
      assert hd(result.events).tool_call.name == "bash"
    end
  end

  describe "parse_kimi_json/1" do
    test "parses passthrough TurnBegin" do
      result = JsonOutput.parse_kimi_json(~s({"type": "TurnBegin"}))
      assert hd(result.events).event_type == "turnbegin"
    end

    test "parses assistant with string content" do
      result = JsonOutput.parse_kimi_json(~s({"role": "assistant", "content": "hello there"}))
      assert result.final_text == "hello there"
      assert hd(result.events).event_type == "assistant"
    end

    test "parses assistant with array content containing text and think" do
      result =
        JsonOutput.parse_kimi_json(
          ~s({"role": "assistant", "content": [{"type": "text", "text": "result"}, {"type": "think", "think": "reasoning"}]})
        )

      assert length(result.events) == 2

      [think_ev, asst_ev] =
        Enum.filter(result.events, fn e -> e.event_type in ["thinking", "assistant"] end)

      assert think_ev.event_type == "thinking"
      assert think_ev.thinking == "reasoning"
      assert asst_ev.event_type == "assistant"
    end

    test "parses tool calls" do
      result =
        JsonOutput.parse_kimi_json(
          ~s({"role": "assistant", "content": "hi", "tool_calls": [{"id": "tc1", "function": {"name": "edit", "arguments": "{}"}}]})
        )

      tc_event = Enum.find(result.events, fn e -> e.event_type == "tool_call" end)
      assert tc_event != nil, "tool_call event not found"
      assert tc_event.tool_call.name == "edit"
    end

    test "parses tool result filtering system tags" do
      result =
        JsonOutput.parse_kimi_json(
          ~s({"role": "tool", "tool_call_id": "tc1", "content": [{"type": "text", "text": "<system>internal</system>"}, {"type": "text", "text": "visible output"}]})
        )

      tr = hd(result.events).tool_result
      assert tr.content == "visible output"
      assert tr.tool_call_id == "tc1"
    end
  end

  describe "parse_json_output/2" do
    test "dispatches to opencode" do
      result = JsonOutput.parse_json_output(~s({"response": "hi"}), "opencode")
      assert result.schema_name == "opencode"
      assert result.final_text == "hi"
    end

    test "dispatches to claude-code" do
      result =
        JsonOutput.parse_json_output(
          ~s({"type": "system", "subtype": "init", "session_id": "s1"}),
          "claude-code"
        )

      assert result.session_id == "s1"
    end

    test "returns error for unknown schema" do
      result = JsonOutput.parse_json_output("", "unknown")
      assert result.error =~ "unknown schema"
    end
  end

  describe "render_parsed/1" do
    test "renders text events" do
      output = %ParsedJsonOutput{
        schema_name: "opencode",
        events: [%JsonEvent{event_type: "text", text: "hello"}],
        final_text: "hello"
      }

      assert JsonOutput.render_parsed(output) == "hello"
    end

    test "renders thinking events" do
      output = %ParsedJsonOutput{
        schema_name: "test",
        events: [%JsonEvent{event_type: "thinking", thinking: "deep thoughts"}]
      }

      assert JsonOutput.render_parsed(output) == "[thinking] deep thoughts"
    end

    test "renders tool use events" do
      output = %ParsedJsonOutput{
        schema_name: "test",
        events: [%JsonEvent{event_type: "tool_use", tool_call: %ToolCall{name: "bash"}}]
      }

      assert JsonOutput.render_parsed(output) == "[tool] bash"
    end

    test "renders error events" do
      output = %ParsedJsonOutput{
        schema_name: "test",
        events: [%JsonEvent{event_type: "error", text: "oops"}]
      }

      assert JsonOutput.render_parsed(output) == "[error] oops"
    end

    test "falls back to final_text when no renderable events" do
      output = %ParsedJsonOutput{
        schema_name: "test",
        events: [%JsonEvent{event_type: "system_retry"}],
        final_text: "fallback"
      }

      assert JsonOutput.render_parsed(output) == "fallback"
    end

    test "renders tool_result events" do
      output = %ParsedJsonOutput{
        schema_name: "test",
        events: [
          %JsonEvent{event_type: "tool_result", tool_result: %ToolResult{content: "file data"}}
        ]
      }

      assert JsonOutput.render_parsed(output) == "[tool_result] file data"
    end

    test "keeps raw Claude stream unknown events from fixture" do
      raw =
        Path.join([@fixtures, "claude", "stream_unknown_events", "stdout.ndjson"])
        |> File.read!()

      result = JsonOutput.parse_claude_code_json(raw)
      rendered = JsonOutput.render_parsed(result)

      assert rendered =~ "Computing the first multiplication."
      assert length(result.raw_lines) >= 10
      assert Enum.any?(result.raw_lines, &(&1["type"] == "rate_limit_event"))
      assert Enum.any?(result.raw_lines, &(&1["type"] == "stream_event" && get_in(&1, ["event", "type"]) == "message_start"))
      assert Enum.any?(result.raw_lines, &(&1["type"] == "stream_event" && get_in(&1, ["event", "type"]) == "message_delta"))
      assert Enum.any?(result.raw_lines, &(&1["type"] == "stream_event" && get_in(&1, ["event", "type"]) == "message_stop"))
      assert Enum.any?(result.raw_lines, &(&1["type"] == "stream_event" && get_in(&1, ["event", "delta", "type"]) == "signature_delta"))
    end
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis/json_output"
require "pathname"

OPENCODE_STDOUT = '{"response":"Hello from OpenCode"}'

CLAUDE_CODE_STDOUT = <<~LINES
  {"type":"system","subtype":"init","session_id":"sess-1","tools":[],"model":"mock","permission_mode":"default"}
  {"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"mock","content":[{"type":"text","text":"I will help you."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"sess-1"}
  {"type":"result","subtype":"success","cost_usd":0.003,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"I will help you.","session_id":"sess-1","usage":{"input_tokens":10,"output_tokens":5}}
LINES

CLAUDE_CODE_TOOL_USE = <<~LINES
  {"type":"system","subtype":"init","session_id":"sess-2","tools":[],"model":"mock","permission_mode":"default"}
  {"type":"tool_use","tool_name":"read_file","tool_input":{"path":"/test.py"},"session_id":"sess-2"}
  {"type":"tool_result","tool_use_id":"toolu_1","content":"file contents","is_error":false,"session_id":"sess-2"}
  {"type":"result","subtype":"success","result":"Done","session_id":"sess-2","cost_usd":0.0,"duration_ms":200,"duration_api_ms":150,"num_turns":2,"usage":{"input_tokens":20,"output_tokens":10}}
LINES

KIMI_STDOUT = '{"role":"assistant","content":"Hello from Kimi"}'

KIMI_WITH_TOOL_CALLS = <<~LINES
  {"role":"assistant","content":"Let me read that.","tool_calls":[{"type":"function","id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\":\\"/src/main.py\\"}"}}]}
  {"role":"tool","content":[{"type":"text","text":"<system>Tool completed successfully.</system>"},{"type":"text","text":"file contents"}],"tool_call_id":"call_1"}
  {"role":"assistant","content":"Done reading the file."}
LINES

KIMI_THINKING = <<~LINES
  {"role":"assistant","content":[{"type":"think","think":"I need to analyze this...","encrypted":null},{"type":"text","text":"Here is my answer"}]}
LINES

FIXTURES = Pathname.new(__dir__).join("..", "..", "tests", "fixtures", "runner-transcripts")

class TestParseOpenCodeJson < Minitest::Test
  def test_simple_response
    result = CallCodingClis::JsonOutput.parse_json_output(OPENCODE_STDOUT, "opencode")
    assert_equal "opencode", result.schema_name
    assert_equal "Hello from OpenCode", result.final_text
    assert_equal 1, result.events.length
    assert_equal "text", result.events[0].event_type
  end

  def test_error_response
    stdout = '{"error":"something went wrong"}'
    result = CallCodingClis::JsonOutput.parse_opencode_json(stdout)
    assert_equal "something went wrong", result.error
    assert_equal 1, result.events.length
    assert_equal "error", result.events[0].event_type
  end
end

class TestParseClaudeCodeJson < Minitest::Test
  def test_simple_response
    result = CallCodingClis::JsonOutput.parse_json_output(CLAUDE_CODE_STDOUT, "claude-code")
    assert_equal "claude-code", result.schema_name
    assert_equal "I will help you.", result.final_text
    assert_equal "sess-1", result.session_id
    assert_in_delta 0.003, result.cost_usd
    assert_equal 100, result.duration_ms
  end

  def test_tool_use_and_result
    result = CallCodingClis::JsonOutput.parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
    assert_equal "Done", result.final_text
    tool_events = result.events.select { |e| e.event_type == "tool_use" }
    assert_equal 1, tool_events.length
    refute_nil tool_events[0].tool_call
    assert_equal "read_file", tool_events[0].tool_call.name
  end

  def test_tool_result
    result = CallCodingClis::JsonOutput.parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
    tr_events = result.events.select { |e| e.event_type == "tool_result" }
    assert_equal 1, tr_events.length
    tr = tr_events[0].tool_result
    refute_nil tr
    assert_equal "toolu_1", tr.tool_call_id
    assert_equal "file contents", tr.content
    refute tr.is_error
  end

  def test_error_result
    stdout = '{"type":"result","subtype":"error","error":"rate limited","session_id":"s1"}'
    result = CallCodingClis::JsonOutput.parse_claude_code_json(stdout)
    assert_equal "rate limited", result.error
  end
end

class TestParseKimiJson < Minitest::Test
  def test_simple_response
    result = CallCodingClis::JsonOutput.parse_json_output(KIMI_STDOUT, "kimi")
    assert_equal "kimi", result.schema_name
    assert_equal "Hello from Kimi", result.final_text
  end

  def test_tool_calls
    result = CallCodingClis::JsonOutput.parse_kimi_json(KIMI_WITH_TOOL_CALLS)
    assert_equal "Done reading the file.", result.final_text
    tc_events = result.events.select { |e| e.event_type == "tool_call" }
    assert_equal 1, tc_events.length
    tc = tc_events[0].tool_call
    refute_nil tc
    assert_equal "read_file", tc.name
  end

  def test_tool_result
    result = CallCodingClis::JsonOutput.parse_kimi_json(KIMI_WITH_TOOL_CALLS)
    tr_events = result.events.select { |e| e.event_type == "tool_result" }
    assert_equal 1, tr_events.length
    tr = tr_events[0].tool_result
    refute_nil tr
    assert_equal "file contents", tr.content
  end

  def test_thinking
    result = CallCodingClis::JsonOutput.parse_kimi_json(KIMI_THINKING)
    think_events = result.events.select { |e| e.event_type == "thinking" }
    assert_equal 1, think_events.length
    assert_equal "I need to analyze this...", think_events[0].thinking
    assert_equal "Here is my answer", result.final_text
  end
end

class TestRenderParsed < Minitest::Test
  def test_render_opencode
    result = CallCodingClis::JsonOutput.parse_opencode_json(OPENCODE_STDOUT)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_equal "Hello from OpenCode", rendered
  end

  def test_render_claude
    result = CallCodingClis::JsonOutput.parse_claude_code_json(CLAUDE_CODE_STDOUT)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_includes rendered, "I will help you."
  end

  def test_render_kimi
    result = CallCodingClis::JsonOutput.parse_kimi_json(KIMI_STDOUT)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_equal "Hello from Kimi", rendered
  end

  def test_render_with_thinking
    result = CallCodingClis::JsonOutput.parse_kimi_json(KIMI_THINKING)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_includes rendered, "[thinking]"
    assert_includes rendered, "Here is my answer"
  end

  def test_render_with_tool_use
    result = CallCodingClis::JsonOutput.parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_includes rendered, "[tool] read_file"
  end

  def test_render_unknown_schema
    result = CallCodingClis::JsonOutput.parse_json_output("{}", "unknown-schema")
    assert_equal "unknown schema: unknown-schema", result.error
  end

  def test_empty_input
    result = CallCodingClis::JsonOutput.parse_opencode_json("")
    assert_equal "", result.final_text
  end

  def test_malformed_json_skipped
    stdout = "not json\n#{OPENCODE_STDOUT}"
    result = CallCodingClis::JsonOutput.parse_opencode_json(stdout)
    assert_equal "Hello from OpenCode", result.final_text
  end

  def test_fixture_claude_stream_unknown_events
    raw = FIXTURES.join("claude", "stream_unknown_events", "stdout.ndjson").read
    result = CallCodingClis::JsonOutput.parse_claude_code_json(raw)
    rendered = CallCodingClis::JsonOutput.render_parsed(result)
    assert_includes rendered, "Computing the first multiplication."
    assert_operator result.raw_lines.length, :>=, 10
    assert result.raw_lines.any? { |obj| obj["type"] == "rate_limit_event" }
    assert result.raw_lines.any? { |obj| obj["type"] == "stream_event" && obj.dig("event", "type") == "message_start" }
    assert result.raw_lines.any? { |obj| obj["type"] == "stream_event" && obj.dig("event", "type") == "message_delta" }
    assert result.raw_lines.any? { |obj| obj["type"] == "stream_event" && obj.dig("event", "type") == "message_stop" }
    assert result.raw_lines.any? { |obj| obj["type"] == "stream_event" && obj.dig("event", "delta", "type") == "signature_delta" }
  end
end

import unittest

from call_coding_clis.json_output import (
    parse_json_output,
    render_parsed,
    parse_opencode_json,
    parse_claude_code_json,
    parse_kimi_json,
    ParsedJsonOutput,
    JsonEvent,
    ToolCall,
    ToolResult,
)


OPENCODE_STDOUT = '{"response":"Hello from OpenCode"}\n'

CLAUDE_CODE_STDOUT = (
    '{"type":"system","subtype":"init","session_id":"sess-1","tools":[],"model":"mock","permission_mode":"default"}\n'
    '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"mock",'
    '"content":[{"type":"text","text":"I will help you."}],"stop_reason":"end_turn","stop_sequence":null,'
    '"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"sess-1"}\n'
    '{"type":"result","subtype":"success","cost_usd":0.003,"duration_ms":100,"duration_api_ms":80,'
    '"num_turns":1,"result":"I will help you.","session_id":"sess-1",'
    '"usage":{"input_tokens":10,"output_tokens":5}}\n'
)

CLAUDE_CODE_TOOL_USE = (
    '{"type":"system","subtype":"init","session_id":"sess-2","tools":[],"model":"mock","permission_mode":"default"}\n'
    '{"type":"tool_use","tool_name":"read_file","tool_input":{"path":"/test.py"},"session_id":"sess-2"}\n'
    '{"type":"tool_result","tool_use_id":"toolu_1","content":"file contents","is_error":false,"session_id":"sess-2"}\n'
    '{"type":"result","subtype":"success","result":"Done","session_id":"sess-2","cost_usd":0.0,"duration_ms":200,'
    '"duration_api_ms":150,"num_turns":2,"usage":{"input_tokens":20,"output_tokens":10}}\n'
)

KIMI_STDOUT = '{"role":"assistant","content":"Hello from Kimi"}\n'

KIMI_WITH_TOOL_CALLS = (
    '{"role":"assistant","content":"Let me read that.",'
    '"tool_calls":[{"type":"function","id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\":\\"/src/main.py\\"}"}}]}\n'
    '{"role":"tool","content":[{"type":"text","text":"<system>Tool completed successfully.</system>"},'
    '{"type":"text","text":"file contents"}],"tool_call_id":"call_1"}\n'
    '{"role":"assistant","content":"Done reading the file."}\n'
)

KIMI_THINKING = (
    '{"role":"assistant","content":['
    '{"type":"think","think":"I need to analyze this...","encrypted":null},'
    '{"type":"text","text":"Here is my answer"}]}\n'
)


class ParseOpenCodeJsonTests(unittest.TestCase):
    def test_simple_response(self):
        result = parse_json_output(OPENCODE_STDOUT, "opencode")
        self.assertEqual(result.schema_name, "opencode")
        self.assertEqual(result.final_text, "Hello from OpenCode")
        self.assertEqual(len(result.events), 1)
        self.assertEqual(result.events[0].event_type, "text")

    def test_error_response(self):
        stdout = '{"error":"something went wrong"}\n'
        result = parse_opencode_json(stdout)
        self.assertEqual(result.error, "something went wrong")
        self.assertEqual(len(result.events), 1)
        self.assertEqual(result.events[0].event_type, "error")


class ParseClaudeCodeJsonTests(unittest.TestCase):
    def test_simple_response(self):
        result = parse_json_output(CLAUDE_CODE_STDOUT, "claude-code")
        self.assertEqual(result.schema_name, "claude-code")
        self.assertEqual(result.final_text, "I will help you.")
        self.assertEqual(result.session_id, "sess-1")
        self.assertEqual(result.cost_usd, 0.003)
        self.assertEqual(result.duration_ms, 100)

    def test_tool_use_and_result(self):
        result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
        self.assertEqual(result.final_text, "Done")
        tool_events = [e for e in result.events if e.event_type == "tool_use"]
        self.assertEqual(len(tool_events), 1)
        tc = tool_events[0].tool_call
        self.assertIsNotNone(tc)
        self.assertEqual(tc.name, "read_file")

    def test_tool_result(self):
        result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
        tr_events = [e for e in result.events if e.event_type == "tool_result"]
        self.assertEqual(len(tr_events), 1)
        tr = tr_events[0].tool_result
        self.assertIsNotNone(tr)
        self.assertEqual(tr.tool_call_id, "toolu_1")
        self.assertEqual(tr.content, "file contents")
        self.assertFalse(tr.is_error)

    def test_error_result(self):
        stdout = '{"type":"result","subtype":"error","error":"rate limited","session_id":"s1"}\n'
        result = parse_claude_code_json(stdout)
        self.assertEqual(result.error, "rate limited")


class ParseKimiJsonTests(unittest.TestCase):
    def test_simple_response(self):
        result = parse_json_output(KIMI_STDOUT, "kimi")
        self.assertEqual(result.schema_name, "kimi")
        self.assertEqual(result.final_text, "Hello from Kimi")

    def test_tool_calls(self):
        result = parse_kimi_json(KIMI_WITH_TOOL_CALLS)
        self.assertEqual(result.final_text, "Done reading the file.")
        tc_events = [e for e in result.events if e.event_type == "tool_call"]
        self.assertEqual(len(tc_events), 1)
        tc = tc_events[0].tool_call
        self.assertIsNotNone(tc)
        self.assertEqual(tc.name, "read_file")

    def test_tool_result(self):
        result = parse_kimi_json(KIMI_WITH_TOOL_CALLS)
        tr_events = [e for e in result.events if e.event_type == "tool_result"]
        self.assertEqual(len(tr_events), 1)
        tr = tr_events[0].tool_result
        self.assertIsNotNone(tr)
        self.assertEqual(tr.content, "file contents")

    def test_thinking(self):
        result = parse_kimi_json(KIMI_THINKING)
        think_events = [e for e in result.events if e.event_type == "thinking"]
        self.assertEqual(len(think_events), 1)
        self.assertEqual(think_events[0].thinking, "I need to analyze this...")
        self.assertEqual(result.final_text, "Here is my answer")


class RenderParsedTests(unittest.TestCase):
    def test_render_opencode(self):
        result = parse_opencode_json(OPENCODE_STDOUT)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "Hello from OpenCode")

    def test_render_claude(self):
        result = parse_claude_code_json(CLAUDE_CODE_STDOUT)
        rendered = render_parsed(result)
        self.assertIn("I will help you.", rendered)

    def test_render_kimi(self):
        result = parse_kimi_json(KIMI_STDOUT)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "Hello from Kimi")

    def test_render_with_thinking(self):
        result = parse_kimi_json(KIMI_THINKING)
        rendered = render_parsed(result)
        self.assertIn("[thinking]", rendered)
        self.assertIn("Here is my answer", rendered)

    def test_render_with_tool_use(self):
        result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
        rendered = render_parsed(result)
        self.assertIn("[tool] read_file", rendered)

    def test_render_unknown_schema(self):
        result = parse_json_output("{}", "unknown-schema")
        self.assertEqual(result.error, "unknown schema: unknown-schema")

    def test_empty_input(self):
        result = parse_opencode_json("")
        self.assertEqual(result.final_text, "")

    def test_malformed_json_skipped(self):
        stdout = "not json\n" + OPENCODE_STDOUT
        result = parse_opencode_json(stdout)
        self.assertEqual(result.final_text, "Hello from OpenCode")


if __name__ == "__main__":
    unittest.main()

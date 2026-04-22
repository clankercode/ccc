import json
import unittest
from pathlib import Path

from call_coding_clis.json_output import (
    FormattedRenderer,
    StructuredStreamProcessor,
    resolve_human_tty,
    parse_json_output,
    render_parsed,
    parse_opencode_json,
    parse_claude_code_json,
    parse_codex_json,
    parse_cursor_agent_json,
    parse_gemini_json,
    parse_kimi_json,
    ParsedJsonOutput,
    JsonEvent,
    ToolCall,
    ToolResult,
)


OPENCODE_STDOUT = '{"response":"Hello from OpenCode"}\n'
OPENCODE_EVENT_STREAM = (
    '{"type":"step_start","timestamp":1,"sessionID":"ses_1","part":{"type":"step-start"}}\n'
    '{"type":"text","timestamp":2,"sessionID":"ses_1","part":{"type":"text","text":"alpha\\nbeta\\ngamma"}}\n'
    '{"type":"step_finish","timestamp":3,"sessionID":"ses_1","part":{"type":"step-finish","tokens":{"total":10,"input":2,"output":3,"reasoning":5,"cache":{"write":0,"read":7}},"cost":0}}\n'
)

OPENCODE_TOOL_STREAM = (
    '{"type":"step_start","timestamp":1,"sessionID":"ses_2","part":{"type":"step-start"}}\n'
    '{"type":"tool_use","timestamp":2,"sessionID":"ses_2","part":{"type":"tool","tool":"read","callID":"call_1","state":{"status":"completed","input":{"filePath":"/tmp/example.txt","offset":1,"limit":1},"output":"<content>1: hello</content>"}}}\n'
    '{"type":"text","timestamp":3,"sessionID":"ses_2","part":{"type":"text","text":"Done reading."}}\n'
)

OPENCODE_REASONING_STREAM = (
    '{"type":"reasoning","timestamp":1,"sessionID":"ses_3","part":{"id":"prt_1","messageID":"msg_1","sessionID":"ses_3","type":"reasoning","text":"Let me think about this.","time":{"start":1},"metadata":{}}}\n'
    '{"type":"text","timestamp":2,"sessionID":"ses_3","part":{"type":"text","text":"Final answer"}}\n'
)

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

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "runner-transcripts"

CLAUDE_CODE_STREAM = (
    '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"Bash"}}}\n'
    '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\":\\"printf \\\\\\"alpha\\\\\\\\nbeta\\\\\\"\\"}"}}}\n'
    '{"type":"tool_result","tool_use_id":"toolu_1","content":"alpha\\nbeta","is_error":false}\n'
    '{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"checking..."}}}\n'
    '{"type":"stream_event","event":{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"hello world"}}}\n'
    '{"type":"result","subtype":"success","result":"hello world"}\n'
)

CLAUDE_UNKNOWN_EVENT = (
    '{"type":"system","subtype":"init","session_id":"sess-3"}\n'
    '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}\n'
)

CURSOR_AGENT_STDOUT = (
    '{"type":"system","subtype":"init","session_id":"cursor-1","model":"Composer 2","permissionMode":"default"}\n'
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello from Cursor"}]},"session_id":"cursor-1"}\n'
    '{"type":"result","subtype":"success","duration_ms":7319,"duration_api_ms":7319,"is_error":false,'
    '"result":"Hello from Cursor","session_id":"cursor-1","usage":{"inputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4}}\n'
)

CODEX_STDOUT = (
    '{"type":"thread.started","thread_id":"thread-1"}\n'
    '{"type":"turn.started"}\n'
    '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Hello from Codex"}}\n'
    '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":3,"output_tokens":2}}\n'
)

CODEX_TOOL_STDOUT = (
    '{"type":"thread.started","thread_id":"thread-2"}\n'
    '{"type":"turn.started"}\n'
    '{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/usr/bin/bash -lc pwd","aggregated_output":"","exit_code":null,"status":"in_progress"}}\n'
    '{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/usr/bin/bash -lc pwd","aggregated_output":"/home/xertrov/src/call-coding-clis\\n","exit_code":0,"status":"completed"}}\n'
    '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"done"}}\n'
    '{"type":"turn.completed","usage":{"input_tokens":20,"cached_input_tokens":4,"output_tokens":5}}\n'
)

GEMINI_STREAM_JSON = (
    '{"type":"init","timestamp":"2026-04-14T06:57:06.152Z","session_id":"gemini-1","model":"auto-gemini-3"}\n'
    '{"type":"message","timestamp":"2026-04-14T06:57:06.153Z","role":"user","content":"Respond with exactly pong"}\n'
    '{"type":"message","timestamp":"2026-04-14T06:57:20.472Z","role":"assistant","content":"pong","delta":true}\n'
    '{"type":"result","timestamp":"2026-04-14T06:57:20.557Z","status":"success","stats":{"total_tokens":14587,"input_tokens":14550,"output_tokens":1,"cached":0,"duration_ms":14405,"tool_calls":0}}\n'
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

    def test_event_stream_response(self):
        result = parse_opencode_json(OPENCODE_EVENT_STREAM)
        self.assertEqual(result.session_id, "ses_1")
        self.assertEqual(result.final_text, "alpha\nbeta\ngamma")
        self.assertEqual(result.events[-1].event_type, "text")
        self.assertEqual(result.usage["total"], 10)
        self.assertEqual(result.usage["cache_read"], 7)

    def test_tool_use_and_result_response(self):
        result = parse_opencode_json(OPENCODE_TOOL_STREAM)
        tool_use_events = [e for e in result.events if e.event_type == "tool_use"]
        tool_result_events = [e for e in result.events if e.event_type == "tool_result"]
        self.assertEqual(len(tool_use_events), 1)
        self.assertEqual(len(tool_result_events), 1)
        self.assertEqual(tool_use_events[0].tool_call.name, "read")
        self.assertEqual(tool_result_events[0].tool_result.tool_call_id, "call_1")
        self.assertEqual(result.final_text, "Done reading.")

    def test_reasoning_event_is_treated_as_thinking(self):
        result = parse_opencode_json(OPENCODE_REASONING_STREAM)
        thinking_events = [e for e in result.events if e.event_type == "thinking"]
        self.assertEqual(result.session_id, "ses_3")
        self.assertEqual(result.final_text, "Final answer")
        self.assertEqual(len(thinking_events), 1)
        self.assertEqual(thinking_events[0].thinking, "Let me think about this.")
        self.assertEqual(result.unknown_json_lines, [])
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn("[thinking] Let me think about this.", rendered)
        self.assertIn("[assistant] Final answer", rendered)
        self.assertNotIn("[thinking] Let me think about this.", render_parsed(result, show_thinking=False))


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


class ParseCursorAgentJsonTests(unittest.TestCase):
    def test_simple_response(self):
        result = parse_json_output(CURSOR_AGENT_STDOUT, "cursor-agent")
        self.assertEqual(result.schema_name, "cursor-agent")
        self.assertEqual(result.final_text, "Hello from Cursor")
        self.assertEqual(result.session_id, "cursor-1")
        self.assertEqual(result.duration_ms, 7319)
        self.assertEqual(result.usage["inputTokens"], 1)
        self.assertEqual(result.usage["outputTokens"], 2)

    def test_error_result(self):
        stdout = '{"type":"result","subtype":"error","is_error":true,"error":"blocked","session_id":"cursor-2"}\n'
        result = parse_cursor_agent_json(stdout)
        self.assertEqual(result.session_id, "cursor-2")
        self.assertEqual(result.error, "blocked")
        self.assertEqual(result.events[0].event_type, "error")


class ParseCodexJsonTests(unittest.TestCase):
    def test_simple_response(self):
        result = parse_json_output(CODEX_STDOUT, "codex")
        self.assertEqual(result.schema_name, "codex")
        self.assertEqual(result.session_id, "thread-1")
        self.assertEqual(result.final_text, "Hello from Codex")
        self.assertEqual(result.usage["input_tokens"], 10)
        self.assertEqual(result.usage["cached_input_tokens"], 3)
        self.assertEqual(result.usage["output_tokens"], 2)
        self.assertEqual(result.unknown_json_lines, [])

    def test_tool_use_and_result_response(self):
        result = parse_codex_json(CODEX_TOOL_STDOUT)
        self.assertEqual(result.final_text, "done")
        tool_use_events = [e for e in result.events if e.event_type == "tool_use_start"]
        tool_result_events = [e for e in result.events if e.event_type == "tool_result"]
        self.assertEqual(len(tool_use_events), 1)
        self.assertEqual(len(tool_result_events), 1)
        self.assertEqual(tool_use_events[0].tool_call.name, "command_execution")
        self.assertIn("pwd", tool_use_events[0].tool_call.arguments)
        self.assertEqual(tool_result_events[0].tool_result.content, "/home/xertrov/src/call-coding-clis\n")
        self.assertFalse(tool_result_events[0].tool_result.is_error)
        self.assertEqual(result.unknown_json_lines, [])

    def test_render_codex_tool_use(self):
        result = parse_codex_json(CODEX_TOOL_STDOUT)
        rendered = render_parsed(result)
        self.assertIn("[tool:start] command_execution: /usr/bin/bash -lc pwd", rendered)
        self.assertIn("[tool:result] command_execution (ok): /usr/bin/bash -lc pwd", rendered)
        self.assertIn("[assistant] done", rendered)

    def test_stream_processor_renders_codex_incrementally(self):
        processor = StructuredStreamProcessor("codex", FormattedRenderer())
        rendered = processor.feed(CODEX_TOOL_STDOUT)
        self.assertIn("[tool:start] command_execution: /usr/bin/bash -lc pwd", rendered)
        self.assertIn("[tool:result] command_execution (ok): /usr/bin/bash -lc pwd", rendered)
        self.assertIn("[assistant] done", rendered)
        self.assertEqual(processor.take_unknown_json_lines(), [])


class ParseGeminiJsonTests(unittest.TestCase):
    def test_stream_json_response(self):
        result = parse_json_output(GEMINI_STREAM_JSON, "gemini")
        self.assertEqual(result.schema_name, "gemini")
        self.assertEqual(result.session_id, "gemini-1")
        self.assertEqual(result.final_text, "pong")
        self.assertEqual(result.usage["total_tokens"], 14587)
        self.assertEqual(result.usage["output_tokens"], 1)
        self.assertEqual(result.duration_ms, 14405)
        self.assertEqual(result.unknown_json_lines, [])

    def test_render_gemini_stream_json(self):
        result = parse_gemini_json(GEMINI_STREAM_JSON)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "[assistant] pong")

    def test_stream_processor_renders_gemini_incrementally(self):
        processor = StructuredStreamProcessor("gemini", FormattedRenderer())
        chunks = []
        for line in GEMINI_STREAM_JSON.splitlines(keepends=True):
            rendered = processor.feed(line)
            if rendered:
                chunks.append(rendered)
        self.assertEqual(chunks, ["[assistant] pong"])
        self.assertEqual(processor.take_unknown_json_lines(), [])


class RenderParsedTests(unittest.TestCase):
    def test_render_opencode(self):
        result = parse_opencode_json(OPENCODE_STDOUT)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "[assistant] Hello from OpenCode")

    def test_render_opencode_uses_color_prefixes_on_tty(self):
        result = parse_opencode_json(OPENCODE_STDOUT)
        rendered = render_parsed(result, tty=True)
        self.assertEqual(rendered, "\x1b[96m💬\x1b[0m Hello from OpenCode")

    def test_render_opencode_tool_use(self):
        result = parse_opencode_json(OPENCODE_TOOL_STREAM)
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn("[tool:start] read", rendered)
        self.assertIn("[tool:result] read (ok)", rendered)
        self.assertIn("[assistant] Done reading.", rendered)

    def test_render_claude(self):
        result = parse_claude_code_json(CLAUDE_CODE_STDOUT)
        rendered = render_parsed(result)
        self.assertIn("I will help you.", rendered)

    def test_render_kimi(self):
        result = parse_kimi_json(KIMI_STDOUT)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "[assistant] Hello from Kimi")

    def test_render_cursor_dedupes_assistant_and_result(self):
        result = parse_cursor_agent_json(CURSOR_AGENT_STDOUT)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "[assistant] Hello from Cursor")

    def test_render_cursor_trims_outer_newlines_from_real_text(self):
        stdout = (
            '{"type":"assistant","message":{"content":[{"type":"text","text":"\\npong"}]}}\n'
            '{"type":"result","subtype":"success","result":"\\npong"}\n'
        )
        result = parse_cursor_agent_json(stdout)
        rendered = render_parsed(result)
        self.assertEqual(rendered, "[assistant] pong")

    def test_render_with_thinking(self):
        result = parse_kimi_json(KIMI_THINKING)
        rendered = render_parsed(result)
        self.assertIn("[thinking]", rendered)
        self.assertIn("Here is my answer", rendered)

    def test_render_with_tool_use(self):
        result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE)
        rendered = render_parsed(result)
        self.assertIn("[tool:start] read_file", rendered)

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

    def test_render_hides_thinking_when_disabled(self):
        result = parse_kimi_json(KIMI_THINKING)
        rendered = render_parsed(result, show_thinking=False)
        self.assertNotIn("[thinking]", rendered)
        self.assertIn("Here is my answer", rendered)

    def test_formatted_renderer_shows_bash_command_preview(self):
        result = parse_claude_code_json(CLAUDE_CODE_STREAM)
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn("[tool:start] Bash", rendered)
        self.assertIn("[tool:result] Bash (ok): printf", rendered)
        self.assertIn("[thinking] checking...", rendered)
        self.assertIn("[assistant] hello world", rendered)
        self.assertNotIn("[ok] hello world", rendered)

    def test_stream_processor_renders_incrementally(self):
        processor = StructuredStreamProcessor(
            "claude-code",
            FormattedRenderer(show_thinking=True, tty=False),
        )
        chunks = []
        for line in CLAUDE_CODE_STREAM.splitlines(keepends=True):
            rendered = processor.feed(line)
            if rendered:
                chunks.append(rendered)
        self.assertTrue(any("[tool:start] Bash" in chunk for chunk in chunks))
        self.assertTrue(any("[thinking] checking..." in chunk for chunk in chunks))
        self.assertTrue(any("[assistant] hello world" in chunk for chunk in chunks))

    def test_cursor_stream_processor_dedupes_assistant_and_result(self):
        processor = StructuredStreamProcessor(
            "cursor-agent",
            FormattedRenderer(show_thinking=False, tty=False),
        )
        chunks = []
        for line in CURSOR_AGENT_STDOUT.splitlines(keepends=True):
            rendered = processor.feed(line)
            if rendered:
                chunks.append(rendered)
        self.assertEqual(chunks, ["[assistant] Hello from Cursor"])

    def test_cursor_stream_processor_trims_outer_newlines(self):
        processor = StructuredStreamProcessor(
            "cursor-agent",
            FormattedRenderer(show_thinking=False, tty=False),
        )
        raw = (
            '{"type":"assistant","message":{"content":[{"type":"text","text":"\\npong"}]}}\n'
            '{"type":"result","subtype":"success","result":"\\npong"}\n'
        )
        chunks = []
        for line in raw.splitlines(keepends=True):
            rendered = processor.feed(line)
            if rendered:
                chunks.append(rendered)
        self.assertEqual(chunks, ["[assistant] pong"])

    def test_stream_processor_dedupes_final_assistant_and_result_after_text_deltas(
        self,
    ):
        raw = (
            '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"DONE"}}}\n'
            '{"type":"assistant","message":{"content":[{"type":"text","text":"DONE"}]}}\n'
            '{"type":"result","subtype":"success","result":"DONE"}\n'
        )
        processor = StructuredStreamProcessor(
            "claude-code",
            FormattedRenderer(show_thinking=False, tty=False),
        )
        chunks = []
        for line in raw.splitlines(keepends=True):
            rendered = processor.feed(line)
            if rendered:
                chunks.append(rendered)
        self.assertEqual(chunks, ["[assistant] DONE"])

    def test_unknown_json_is_captured_but_not_rendered_by_default(self):
        result = parse_claude_code_json(CLAUDE_UNKNOWN_EVENT)
        self.assertEqual(render_parsed(result, show_thinking=True), "")
        self.assertEqual(result.unknown_json_lines, [])

    def test_resolve_human_tty_defaults_to_terminal_state(self):
        self.assertTrue(resolve_human_tty(True))
        self.assertFalse(resolve_human_tty(False))

    def test_resolve_human_tty_force_color_wins(self):
        self.assertTrue(resolve_human_tty(False, force_color="1"))
        self.assertTrue(resolve_human_tty(True, force_color="1", no_color="1"))

    def test_resolve_human_tty_no_color_disables(self):
        self.assertFalse(resolve_human_tty(True, no_color="1"))

    def test_fixture_claude_tool_bash(self):
        raw = (FIXTURES / "claude" / "tool_bash" / "stdout.ndjson").read_text()
        result = parse_claude_code_json(raw)
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn("[tool:start] Bash", rendered)
        self.assertIn("[tool:result] Bash (ok): echo", rendered)
        self.assertIn("[assistant] done.", rendered)

    def test_fixture_claude_stream_unknown_events(self):
        raw = (
            FIXTURES / "claude" / "stream_unknown_events" / "stdout.ndjson"
        ).read_text()
        result = parse_claude_code_json(raw)
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn(
            "[thinking] The user wants a staged tool-using response.", rendered
        )
        self.assertIn("[assistant] Computing the first multiplication.", rendered)
        self.assertEqual(result.unknown_json_lines, [])

    def test_claude_new_system_subtypes_are_handled(self):
        subtypes = [
            "hook_progress",
            "compact_boundary",
            "post_turn_summary",
            "local_command_output",
            "files_persisted",
            "task_notification",
            "task_started",
            "task_progress",
            "session_state_changed",
            "elicitation_complete",
            "bridge_state",
        ]
        raw = "".join(
            json.dumps({"type": "system", "subtype": s}) + "\n" for s in subtypes
        )
        result = parse_claude_code_json(raw)
        self.assertEqual(result.unknown_json_lines, [])
        self.assertEqual(render_parsed(result, show_thinking=True), "")

    def test_claude_new_top_level_types_are_handled(self):
        types = [
            "tool_progress",
            "tool_use_summary",
            "auth_status",
            "streamlined_text",
            "streamlined_tool_use_summary",
            "prompt_suggestion",
        ]
        raw = "".join(json.dumps({"type": t}) + "\n" for t in types)
        result = parse_claude_code_json(raw)
        self.assertEqual(result.unknown_json_lines, [])

    def test_claude_user_without_tool_results_is_handled(self):
        raw = '{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}\n'
        result = parse_claude_code_json(raw)
        self.assertEqual(result.unknown_json_lines, [])

    def test_claude_stream_event_new_block_and_delta_types_are_handled(self):
        lines = [
            {"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "server_tool_use"}}},
            {"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "connector_text"}}},
            {"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "advisor_tool_result"}}},
            {"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "citations_delta"}}},
            {"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "connector_text_delta"}}},
        ]
        raw = "".join(json.dumps(l) + "\n" for l in lines)
        result = parse_claude_code_json(raw)
        self.assertEqual(result.unknown_json_lines, [])

    def test_claude_result_error_subtypes_produce_error_events(self):
        for subtype in [
            "error_during_execution",
            "error_max_turns",
            "error_max_budget_usd",
            "error_max_structured_output_retries",
        ]:
            with self.subTest(subtype=subtype):
                raw = json.dumps({"type": "result", "subtype": subtype, "error": "boom"}) + "\n"
                result = parse_claude_code_json(raw)
                self.assertEqual(result.unknown_json_lines, [])
                self.assertTrue(any(e.event_type == "error" for e in result.events))
                self.assertEqual(result.error, "boom")

    def test_fixture_kimi_tool_bash(self):
        raw = (FIXTURES / "kimi" / "tool_bash" / "stdout.ndjson").read_text()
        result = parse_kimi_json(raw)
        rendered = render_parsed(result, show_thinking=True)
        self.assertIn("[tool:start] Shell", rendered)
        self.assertIn("[tool:result] Shell (ok): echo", rendered)
        self.assertIn("[assistant] done", rendered)


if __name__ == "__main__":
    unittest.main()

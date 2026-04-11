use call_coding_clis::*;
use std::fs;
use std::path::PathBuf;

fn fixture(path: &str) -> String {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("tests/fixtures/runner-transcripts");
    fs::read_to_string(root.join(path)).unwrap()
}

#[test]
fn test_opencode_simple_response() {
    let raw = "{\"response\":\"hello world\"}\n";
    let parsed = parse_opencode_json(raw);
    assert_eq!(parsed.schema_name, "opencode");
    assert_eq!(parsed.final_text, "hello world");
    assert_eq!(parsed.events.len(), 1);
    assert_eq!(parsed.events[0].event_type, "text");
    assert_eq!(parsed.events[0].text, "hello world");
}

#[test]
fn test_opencode_error_response() {
    let raw = "{\"error\":\"something broke\"}\n";
    let parsed = parse_opencode_json(raw);
    assert_eq!(parsed.error, "something broke");
    assert_eq!(parsed.events.len(), 1);
    assert_eq!(parsed.events[0].event_type, "error");
    assert_eq!(parsed.events[0].text, "something broke");
    assert_eq!(parsed.final_text, "");
}

#[test]
fn test_opencode_event_stream_response() {
    let raw = concat!(
        "{\"type\":\"step_start\",\"timestamp\":1,\"sessionID\":\"ses_1\",\"part\":{\"type\":\"step-start\"}}\n",
        "{\"type\":\"text\",\"timestamp\":2,\"sessionID\":\"ses_1\",\"part\":{\"type\":\"text\",\"text\":\"alpha\\nbeta\\ngamma\"}}\n",
        "{\"type\":\"step_finish\",\"timestamp\":3,\"sessionID\":\"ses_1\",\"part\":{\"type\":\"step-finish\",\"tokens\":{\"total\":10,\"input\":2,\"output\":3,\"reasoning\":5,\"cache\":{\"write\":0,\"read\":7}},\"cost\":0}}\n"
    );
    let parsed = parse_opencode_json(raw);
    assert_eq!(parsed.session_id, "ses_1");
    assert_eq!(parsed.final_text, "alpha\nbeta\ngamma");
    assert_eq!(parsed.events.last().unwrap().event_type, "text");
    assert_eq!(parsed.usage.get("total").copied(), Some(10));
    assert_eq!(parsed.usage.get("cache_read").copied(), Some(7));
}

#[test]
fn test_opencode_tool_use_and_result_response() {
    let raw = concat!(
        "{\"type\":\"step_start\",\"timestamp\":1,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"step-start\"}}\n",
        "{\"type\":\"tool_use\",\"timestamp\":2,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"tool\",\"tool\":\"read\",\"callID\":\"call_1\",\"state\":{\"status\":\"completed\",\"input\":{\"filePath\":\"/tmp/example.txt\",\"offset\":1,\"limit\":1},\"output\":\"<content>1: hello</content>\"}}}\n",
        "{\"type\":\"text\",\"timestamp\":3,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"text\",\"text\":\"Done reading.\"}}\n"
    );
    let parsed = parse_opencode_json(raw);
    let tool_use_events: Vec<_> = parsed
        .events
        .iter()
        .filter(|event| event.event_type == "tool_use")
        .collect();
    let tool_result_events: Vec<_> = parsed
        .events
        .iter()
        .filter(|event| event.event_type == "tool_result")
        .collect();
    assert_eq!(tool_use_events.len(), 1);
    assert_eq!(tool_result_events.len(), 1);
    assert_eq!(tool_use_events[0].tool_call.as_ref().unwrap().name, "read");
    assert_eq!(
        tool_result_events[0]
            .tool_result
            .as_ref()
            .unwrap()
            .tool_call_id,
        "call_1"
    );
    assert_eq!(parsed.final_text, "Done reading.");
}

#[test]
fn test_claude_code_simple_response() {
    let raw = concat!(
        "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-123\"}\n",
        "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi there\"}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}\n",
        "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"hi there\",\"cost_usd\":0.003,\"duration_ms\":1500}\n"
    );
    let parsed = parse_claude_code_json(raw);
    assert_eq!(parsed.schema_name, "claude-code");
    assert_eq!(parsed.session_id, "sess-123");
    assert_eq!(parsed.final_text, "hi there");
    assert_eq!(parsed.cost_usd, 0.003);
    assert_eq!(parsed.duration_ms, 1500);
    assert_eq!(parsed.usage.get("input_tokens").copied(), Some(10));
    assert_eq!(parsed.usage.get("output_tokens").copied(), Some(5));
}

#[test]
fn test_claude_code_tool_use_and_result() {
    let raw = concat!(
        "{\"type\":\"tool_use\",\"tool_name\":\"Read\",\"tool_input\":{\"file\":\"src/main.rs\"}}\n",
        "{\"type\":\"tool_result\",\"tool_use_id\":\"tu-1\",\"content\":\"fn main() {}\",\"is_error\":false}\n"
    );
    let parsed = parse_claude_code_json(raw);
    assert_eq!(parsed.events.len(), 2);

    assert_eq!(parsed.events[0].event_type, "tool_use");
    let tc = parsed.events[0].tool_call.as_ref().unwrap();
    assert_eq!(tc.name, "Read");
    assert!(tc.arguments.contains("src/main.rs"));

    assert_eq!(parsed.events[1].event_type, "tool_result");
    let tr = parsed.events[1].tool_result.as_ref().unwrap();
    assert_eq!(tr.tool_call_id, "tu-1");
    assert_eq!(tr.content, "fn main() {}");
    assert!(!tr.is_error);
}

#[test]
fn test_claude_code_error() {
    let raw = "{\"type\":\"result\",\"subtype\":\"error\",\"error\":\"rate limited\"}\n";
    let parsed = parse_claude_code_json(raw);
    assert_eq!(parsed.error, "rate limited");
    assert_eq!(parsed.events.len(), 1);
    assert_eq!(parsed.events[0].event_type, "error");
}

#[test]
fn test_kimi_simple_response() {
    let raw = "{\"role\":\"assistant\",\"content\":\"hello from kimi\"}\n";
    let parsed = parse_kimi_json(raw);
    assert_eq!(parsed.schema_name, "kimi");
    assert_eq!(parsed.final_text, "hello from kimi");
    assert_eq!(parsed.events.len(), 1);
    assert_eq!(parsed.events[0].event_type, "assistant");
}

#[test]
fn test_kimi_tool_calls() {
    let raw = concat!(
        "{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"tc-1\",\"function\":{\"name\":\"Read\",\"arguments\":\"{\\\"file\\\":\\\"a.rs\\\"}\"}}]}\n"
    );
    let parsed = parse_kimi_json(raw);
    let tc_event = parsed
        .events
        .iter()
        .find(|e| e.event_type == "tool_call")
        .unwrap();
    let tc = tc_event.tool_call.as_ref().unwrap();
    assert_eq!(tc.id, "tc-1");
    assert_eq!(tc.name, "Read");
    assert!(tc.arguments.contains("a.rs"));
}

#[test]
fn test_kimi_tool_result() {
    let raw = "{\"role\":\"tool\",\"tool_call_id\":\"tc-1\",\"content\":[{\"type\":\"text\",\"text\":\"file contents here\"}]}\n";
    let parsed = parse_kimi_json(raw);
    assert_eq!(parsed.events.len(), 1);
    let tr = parsed.events[0].tool_result.as_ref().unwrap();
    assert_eq!(tr.tool_call_id, "tc-1");
    assert_eq!(tr.content, "file contents here");
}

#[test]
fn test_kimi_thinking() {
    let raw = "{\"role\":\"assistant\",\"content\":[{\"type\":\"think\",\"think\":\"pondering...\"},{\"type\":\"text\",\"text\":\"answer\"}]}\n";
    let parsed = parse_kimi_json(raw);
    assert_eq!(parsed.events.len(), 2);
    assert_eq!(parsed.events[0].event_type, "thinking");
    assert_eq!(parsed.events[0].thinking, "pondering...");
    assert_eq!(parsed.events[1].event_type, "assistant");
    assert_eq!(parsed.events[1].text, "answer");
    assert_eq!(parsed.final_text, "answer");
}

#[test]
fn test_kimi_tool_result_filters_system() {
    let raw = "{\"role\":\"tool\",\"tool_call_id\":\"tc-2\",\"content\":[{\"type\":\"text\",\"text\":\"<system>internal</system>\"},{\"type\":\"text\",\"text\":\"real output\"}]}\n";
    let parsed = parse_kimi_json(raw);
    let tr = parsed.events[0].tool_result.as_ref().unwrap();
    assert_eq!(tr.content, "real output");
}

#[test]
fn test_kimi_passthrough_events() {
    let raw = "{\"type\":\"TurnBegin\"}\n{\"type\":\"StepBegin\"}\n{\"type\":\"StatusUpdate\"}\n";
    let parsed = parse_kimi_json(raw);
    assert_eq!(parsed.events.len(), 3);
    assert_eq!(parsed.events[0].event_type, "turnbegin");
    assert_eq!(parsed.events[1].event_type, "stepbegin");
    assert_eq!(parsed.events[2].event_type, "statusupdate");
}

#[test]
fn test_render_opencode() {
    let raw = "{\"response\":\"hello\"}\n";
    let parsed = parse_opencode_json(raw);
    let rendered = render_parsed(&parsed, true, false);
    assert_eq!(rendered, "[assistant] hello");
}

#[test]
fn test_render_opencode_uses_color_prefixes_on_tty() {
    let raw = "{\"response\":\"hello\"}\n";
    let parsed = parse_opencode_json(raw);
    let rendered = render_parsed(&parsed, true, true);
    assert_eq!(rendered, "\u{1b}[96m💬\u{1b}[0m hello");
}

#[test]
fn test_render_opencode_tool_use() {
    let raw = concat!(
        "{\"type\":\"step_start\",\"timestamp\":1,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"step-start\"}}\n",
        "{\"type\":\"tool_use\",\"timestamp\":2,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"tool\",\"tool\":\"read\",\"callID\":\"call_1\",\"state\":{\"status\":\"completed\",\"input\":{\"filePath\":\"/tmp/example.txt\",\"offset\":1,\"limit\":1},\"output\":\"<content>1: hello</content>\"}}}\n",
        "{\"type\":\"text\",\"timestamp\":3,\"sessionID\":\"ses_2\",\"part\":{\"type\":\"text\",\"text\":\"Done reading.\"}}\n"
    );
    let parsed = parse_opencode_json(raw);
    let rendered = render_parsed(&parsed, true, false);
    assert!(rendered.contains("[tool:start] read"));
    assert!(rendered.contains("[tool:result] read (ok)"));
    assert!(rendered.contains("[assistant] Done reading."));
}

#[test]
fn test_render_claude_code_tool_use() {
    let raw = "{\"type\":\"tool_use\",\"tool_name\":\"Bash\",\"tool_input\":{\"cmd\":\"ls\"}}\n";
    let parsed = parse_claude_code_json(raw);
    let rendered = render_parsed(&parsed, true, false);
    assert_eq!(rendered, "[tool:start] Bash: ls");
}

#[test]
fn test_render_claude_code_tool_use_truncates_unicode_safely() {
    let command = format!("{}🛠️tail", "a".repeat(399));
    let raw = serde_json::json!({
        "type": "tool_use",
        "tool_name": "Bash",
        "tool_input": {"cmd": command}
    })
    .to_string()
        + "\n";
    let parsed = parse_claude_code_json(&raw);
    let rendered = render_parsed(&parsed, true, false);

    assert!(rendered.starts_with("[tool:start] Bash: "));
    assert!(rendered.ends_with(" …"));
}

#[test]
fn test_render_claude_code_tool_result_truncates_unicode_safely() {
    let content = format!("{}🛠️tail", "a".repeat(399));
    let raw = serde_json::json!({
        "type": "tool_result",
        "tool_use_id": "toolu_1",
        "content": content,
        "is_error": false
    })
    .to_string()
        + "\n";
    let parsed = parse_claude_code_json(&raw);
    let rendered = render_parsed(&parsed, true, false);

    assert!(rendered.starts_with("[tool:result] tool (ok)\n"));
    assert!(rendered.ends_with(" …"));
}

#[test]
fn test_render_kimi_thinking() {
    let raw = "{\"role\":\"assistant\",\"content\":[{\"type\":\"think\",\"think\":\"hmm\"},{\"type\":\"text\",\"text\":\"ok\"}]}\n";
    let parsed = parse_kimi_json(raw);
    let rendered = render_parsed(&parsed, true, false);
    assert!(rendered.contains("[thinking] hmm"));
    assert!(rendered.contains("ok"));
}

#[test]
fn test_render_unknown_schema() {
    let parsed = parse_json_output("", "nonexistent");
    let rendered = render_parsed(&parsed, true, false);
    assert_eq!(rendered, "");
    assert_eq!(parsed.error, "unknown schema: nonexistent");
}

#[test]
fn test_empty_input() {
    let parsed = parse_json_output("", "opencode");
    assert_eq!(parsed.events.len(), 0);
    assert_eq!(parsed.final_text, "");
    let rendered = render_parsed(&parsed, true, false);
    assert_eq!(rendered, "");
}

#[test]
fn test_malformed_json_skipped() {
    let raw = "not json at all\n{\"response\":\"valid\"}\nalso not json\n";
    let parsed = parse_opencode_json(raw);
    assert_eq!(parsed.events.len(), 1);
    assert_eq!(parsed.final_text, "valid");
}

#[test]
fn test_render_error_event() {
    let raw = "{\"error\":\"bad\"}\n";
    let parsed = parse_opencode_json(raw);
    let rendered = render_parsed(&parsed, true, false);
    assert_eq!(rendered, "[error] bad");
}

#[test]
fn test_resolve_human_tty_defaults_to_terminal_state() {
    assert!(resolve_human_tty(true, None, None));
    assert!(!resolve_human_tty(false, None, None));
}

#[test]
fn test_resolve_human_tty_force_color_wins() {
    assert!(resolve_human_tty(false, Some("1"), None));
    assert!(resolve_human_tty(true, Some("1"), Some("1")));
}

#[test]
fn test_resolve_human_tty_no_color_disables() {
    assert!(!resolve_human_tty(true, None, Some("1")));
}

#[test]
fn test_stream_processor_renders_incrementally() {
    let raw = concat!(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"Bash\"}}}\n",
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"command\\\":\\\"printf hi\\\"}\"}}}\n",
        "{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":\"hi\",\"is_error\":false}\n",
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"checking\"}}}\n",
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"done\"}}}\n"
    );
    let mut processor =
        StructuredStreamProcessor::new("claude-code", FormattedRenderer::new(true, false));
    let mut chunks = Vec::new();
    for line in raw.lines() {
        let rendered = processor.feed(&(line.to_string() + "\n"));
        if !rendered.is_empty() {
            chunks.push(rendered);
        }
    }
    assert!(chunks
        .iter()
        .any(|chunk| chunk.contains("[tool:start] Bash")));
    assert!(chunks
        .iter()
        .any(|chunk| chunk.contains("[tool:result] Bash (ok): printf hi")));
    assert!(chunks
        .iter()
        .any(|chunk| chunk.contains("[thinking] checking")));
    assert!(chunks
        .iter()
        .any(|chunk| chunk.contains("[assistant] done")));
}

#[test]
fn test_stream_processor_dedupes_final_assistant_and_result_after_text_deltas() {
    let raw = concat!(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"DONE\"}}}\n",
        "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"DONE\"}]}}\n",
        "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"DONE\"}\n"
    );
    let mut processor =
        StructuredStreamProcessor::new("claude-code", FormattedRenderer::new(false, false));
    let mut chunks = Vec::new();
    for line in raw.lines() {
        let rendered = processor.feed(&(line.to_string() + "\n"));
        if !rendered.is_empty() {
            chunks.push(rendered);
        }
    }
    assert_eq!(chunks, vec!["[assistant] DONE"]);
}

#[test]
fn test_fixture_claude_tool_bash() {
    let raw = fixture("claude/tool_bash/stdout.ndjson");
    let parsed = parse_claude_code_json(&raw);
    let rendered = render_parsed(&parsed, true, false);
    assert!(rendered.contains("[tool:start] Bash"));
    assert!(rendered.contains("[tool:result] Bash (ok): echo"));
    assert!(rendered.contains("[assistant] done."));
}

#[test]
fn test_fixture_claude_stream_unknown_events() {
    let raw = fixture("claude/stream_unknown_events/stdout.ndjson");
    let parsed = parse_claude_code_json(&raw);
    let rendered = render_parsed(&parsed, true, false);
    assert!(rendered.contains("[thinking] The user wants a staged tool-using response."));
    assert!(rendered.contains("[assistant] Computing the first multiplication."));
    assert!(parsed.unknown_json_lines.len() >= 6);
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"message_start\"")));
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"signature_delta\"")));
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"content_block_stop\"")));
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"message_delta\"")));
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"message_stop\"")));
    assert!(parsed
        .unknown_json_lines
        .iter()
        .any(|line| line.contains("\"type\":\"rate_limit_event\"")));
}

#[test]
fn test_fixture_kimi_tool_bash() {
    let raw = fixture("kimi/tool_bash/stdout.ndjson");
    let parsed = parse_kimi_json(&raw);
    let rendered = render_parsed(&parsed, true, false);
    assert!(rendered.contains("[tool:start] Shell"));
    assert!(rendered.contains("[tool:result] Shell (ok): echo"));
    assert!(rendered.contains("[assistant] done"));
}

#[test]
fn test_claude_code_streaming_thinking() {
    let raw = concat!(
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"content_block\":{\"type\":\"thinking\"}}}\n",
        "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"let me think\"}}}\n"
    );
    let parsed = parse_claude_code_json(raw);
    assert_eq!(parsed.events.len(), 2);
    assert_eq!(parsed.events[0].event_type, "thinking_start");
    assert_eq!(parsed.events[1].event_type, "thinking_delta");
    assert_eq!(parsed.events[1].thinking, "let me think");
}

#[test]
fn test_unknown_json_is_captured_but_not_rendered_by_default() {
    let raw = concat!(
        "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-1\"}\n",
        "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed\"}}\n"
    );
    let parsed = parse_claude_code_json(raw);
    assert_eq!(render_parsed(&parsed, true, false), "");
    assert_eq!(parsed.unknown_json_lines.len(), 1);
    assert!(parsed.unknown_json_lines[0].contains("\"type\":\"rate_limit_event\""));
}

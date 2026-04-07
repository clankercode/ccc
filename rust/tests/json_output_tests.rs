use call_coding_clis::*;

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
    let rendered = render_parsed(&parsed);
    assert_eq!(rendered, "hello");
}

#[test]
fn test_render_claude_code_tool_use() {
    let raw = "{\"type\":\"tool_use\",\"tool_name\":\"Bash\",\"tool_input\":{\"cmd\":\"ls\"}}\n";
    let parsed = parse_claude_code_json(raw);
    let rendered = render_parsed(&parsed);
    assert_eq!(rendered, "[tool] Bash");
}

#[test]
fn test_render_kimi_thinking() {
    let raw = "{\"role\":\"assistant\",\"content\":[{\"type\":\"think\",\"think\":\"hmm\"},{\"type\":\"text\",\"text\":\"ok\"}]}\n";
    let parsed = parse_kimi_json(raw);
    let rendered = render_parsed(&parsed);
    assert!(rendered.contains("[thinking] hmm"));
    assert!(rendered.contains("ok"));
}

#[test]
fn test_render_unknown_schema() {
    let parsed = parse_json_output("", "nonexistent");
    let rendered = render_parsed(&parsed);
    assert_eq!(rendered, "");
    assert_eq!(parsed.error, "unknown schema: nonexistent");
}

#[test]
fn test_empty_input() {
    let parsed = parse_json_output("", "opencode");
    assert_eq!(parsed.events.len(), 0);
    assert_eq!(parsed.final_text, "");
    let rendered = render_parsed(&parsed);
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
    let rendered = render_parsed(&parsed);
    assert_eq!(rendered, "[error] bad");
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

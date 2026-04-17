use super::model::{Event, ToolCall, ToolResult, Transcript, Usage};
use crate::invoke::RunnerKind;

pub fn parse_transcript(raw: &str, schema: &str) -> Transcript {
    transcript_from_parsed(crate::json_output::parse_json_output(raw, schema))
}

pub fn parse_transcript_for_runner(raw: &str, runner: RunnerKind) -> Option<Transcript> {
    schema_name_for_runner(runner).map(|schema| parse_transcript(raw, schema))
}

pub fn schema_name_for_runner(runner: RunnerKind) -> Option<&'static str> {
    match runner {
        RunnerKind::OpenCode => Some("opencode"),
        RunnerKind::Claude => Some("claude-code"),
        RunnerKind::Codex => Some("codex"),
        RunnerKind::Kimi => Some("kimi"),
        RunnerKind::Cursor => Some("cursor-agent"),
        RunnerKind::Gemini => Some("gemini"),
        RunnerKind::RooCode | RunnerKind::Crush => None,
    }
}

pub fn transcript_from_parsed(parsed: crate::json_output::ParsedJsonOutput) -> Transcript {
    Transcript {
        events: parsed.events.into_iter().map(convert_event).collect(),
        final_text: parsed.final_text,
        session_id: (!parsed.session_id.is_empty()).then_some(parsed.session_id),
        usage: Usage {
            counts: parsed.usage,
            cost_usd: parsed.cost_usd,
            duration_ms: parsed.duration_ms,
        },
        error: (!parsed.error.is_empty()).then_some(parsed.error),
        unknown_json_lines: parsed.unknown_json_lines,
    }
}

fn convert_event(event: crate::json_output::JsonEvent) -> Event {
    if let Some(tool_call) = event.tool_call {
        return Event::ToolCall(ToolCall {
            id: tool_call.id,
            name: tool_call.name,
            arguments: tool_call.arguments,
        });
    }
    if let Some(tool_result) = event.tool_result {
        return Event::ToolResult(ToolResult {
            tool_call_id: tool_result.tool_call_id,
            content: tool_result.content,
            is_error: tool_result.is_error,
        });
    }
    if !event.thinking.is_empty() {
        return Event::Thinking(event.thinking);
    }
    match event.event_type.as_str() {
        "error" => Event::Error(event.text),
        "raw_unknown_json" => Event::RawUnknownJson(event.text),
        _ => Event::Text(event.text),
    }
}

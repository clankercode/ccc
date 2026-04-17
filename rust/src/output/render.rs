use super::model::{Event, Transcript};

pub fn render_transcript(transcript: &Transcript, show_thinking: bool, tty: bool) -> String {
    crate::json_output::render_parsed(&parsed_output_from_transcript(transcript), show_thinking, tty)
}

fn parsed_output_from_transcript(transcript: &Transcript) -> crate::json_output::ParsedJsonOutput {
    crate::json_output::ParsedJsonOutput {
        schema_name: String::new(),
        events: transcript
            .events
            .iter()
            .map(event_to_json_event)
            .collect(),
        final_text: transcript.final_text.clone(),
        session_id: transcript.session_id.clone().unwrap_or_default(),
        error: transcript.error.clone().unwrap_or_default(),
        usage: transcript.usage.counts.clone(),
        cost_usd: transcript.usage.cost_usd,
        duration_ms: transcript.usage.duration_ms,
        unknown_json_lines: transcript.unknown_json_lines.clone(),
    }
}

fn event_to_json_event(event: &Event) -> crate::json_output::JsonEvent {
    match event {
        Event::Text(text) => crate::json_output::JsonEvent {
            event_type: "text".into(),
            text: text.clone(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        },
        Event::Thinking(thinking) => crate::json_output::JsonEvent {
            event_type: "thinking".into(),
            text: String::new(),
            thinking: thinking.clone(),
            tool_call: None,
            tool_result: None,
        },
        Event::ToolCall(tool_call) => crate::json_output::JsonEvent {
            event_type: "tool_use".into(),
            text: String::new(),
            thinking: String::new(),
            tool_call: Some(crate::json_output::ToolCall {
                id: tool_call.id.clone(),
                name: tool_call.name.clone(),
                arguments: tool_call.arguments.clone(),
            }),
            tool_result: None,
        },
        Event::ToolResult(tool_result) => crate::json_output::JsonEvent {
            event_type: "tool_result".into(),
            text: String::new(),
            thinking: String::new(),
            tool_call: None,
            tool_result: Some(crate::json_output::ToolResult {
                tool_call_id: tool_result.tool_call_id.clone(),
                content: tool_result.content.clone(),
                is_error: tool_result.is_error,
            }),
        },
        Event::Error(error) => crate::json_output::JsonEvent {
            event_type: "error".into(),
            text: error.clone(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        },
        Event::RawUnknownJson(raw) => crate::json_output::JsonEvent {
            event_type: "raw_unknown_json".into(),
            text: raw.clone(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        },
    }
}

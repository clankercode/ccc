use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TextContent {
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ThinkingContent {
    pub thinking: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolResult {
    pub tool_call_id: String,
    pub content: String,
    pub is_error: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct JsonEvent {
    pub event_type: String,
    pub text: String,
    pub thinking: String,
    pub tool_call: Option<ToolCall>,
    pub tool_result: Option<ToolResult>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParsedJsonOutput {
    pub schema_name: String,
    pub events: Vec<JsonEvent>,
    pub final_text: String,
    pub session_id: String,
    pub error: String,
    pub usage: BTreeMap<String, i64>,
    pub cost_usd: f64,
    pub duration_ms: i64,
    pub unknown_json_lines: Vec<String>,
}

fn new_output(schema_name: &str) -> ParsedJsonOutput {
    ParsedJsonOutput {
        schema_name: schema_name.into(),
        events: Vec::new(),
        final_text: String::new(),
        session_id: String::new(),
        error: String::new(),
        usage: BTreeMap::new(),
        cost_usd: 0.0,
        duration_ms: 0,
        unknown_json_lines: Vec::new(),
    }
}

fn parser_state(
    result: &ParsedJsonOutput,
) -> (
    usize,
    String,
    String,
    String,
    BTreeMap<String, i64>,
    i64,
    u64,
) {
    (
        result.events.len(),
        result.final_text.clone(),
        result.error.clone(),
        result.session_id.clone(),
        result.usage.clone(),
        result.duration_ms,
        result.cost_usd.to_bits(),
    )
}

fn parse_json_line(line: &str) -> Option<serde_json::Value> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }
    let value: serde_json::Value = serde_json::from_str(trimmed).ok()?;
    if value.is_object() {
        Some(value)
    } else {
        None
    }
}

fn apply_opencode_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) {
    if let Some(text) = obj.get("response").and_then(|value| value.as_str()) {
        result.final_text = text.to_string();
        result.events.push(JsonEvent {
            event_type: "text".into(),
            text: text.into(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        });
    } else if let Some(err) = obj.get("error").and_then(|value| value.as_str()) {
        result.error = err.to_string();
        result.events.push(JsonEvent {
            event_type: "error".into(),
            text: err.into(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        });
    } else if obj.get("type").and_then(|value| value.as_str()) == Some("step_start") {
        result.session_id = obj
            .get("sessionID")
            .and_then(|value| value.as_str())
            .unwrap_or(&result.session_id)
            .to_string();
    } else if obj.get("type").and_then(|value| value.as_str()) == Some("text") {
        if let Some(part) = obj.get("part").and_then(|value| value.as_object()) {
            if let Some(text) = part.get("text").and_then(|value| value.as_str()) {
                if !text.is_empty() {
                    result.final_text = text.to_string();
                    result.events.push(JsonEvent {
                        event_type: "text".into(),
                        text: text.into(),
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
            }
        }
    } else if obj.get("type").and_then(|value| value.as_str()) == Some("tool_use") {
        if let Some(part) = obj.get("part").and_then(|value| value.as_object()) {
            let tool_name = part
                .get("tool")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            let call_id = part
                .get("callID")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            let state = part
                .get("state")
                .and_then(|value| value.as_object())
                .cloned()
                .unwrap_or_default();
            let tool_input = state
                .get("input")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let tool_output = state
                .get("output")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            let is_error = state
                .get("status")
                .and_then(|value| value.as_str())
                .map(|value| value.eq_ignore_ascii_case("error"))
                .unwrap_or(false);
            result.events.push(JsonEvent {
                event_type: "tool_use".into(),
                text: String::new(),
                thinking: String::new(),
                tool_call: Some(ToolCall {
                    id: call_id.clone(),
                    name: tool_name,
                    arguments: serde_json::to_string(&tool_input).unwrap_or_default(),
                }),
                tool_result: None,
            });
            result.events.push(JsonEvent {
                event_type: "tool_result".into(),
                text: String::new(),
                thinking: String::new(),
                tool_call: None,
                tool_result: Some(ToolResult {
                    tool_call_id: call_id,
                    content: tool_output,
                    is_error,
                }),
            });
        }
    } else if obj.get("type").and_then(|value| value.as_str()) == Some("step_finish") {
        if let Some(part) = obj.get("part").and_then(|value| value.as_object()) {
            if let Some(tokens) = part.get("tokens").and_then(|value| value.as_object()) {
                let mut usage = BTreeMap::new();
                for key in ["total", "input", "output", "reasoning"] {
                    if let Some(value) = tokens.get(key).and_then(|value| value.as_i64()) {
                        usage.insert(key.to_string(), value);
                    }
                }
                if let Some(cache) = tokens.get("cache").and_then(|value| value.as_object()) {
                    for key in ["write", "read"] {
                        if let Some(value) = cache.get(key).and_then(|value| value.as_i64()) {
                            usage.insert(format!("cache_{key}"), value);
                        }
                    }
                }
                if !usage.is_empty() {
                    result.usage = usage;
                }
            }
            if let Some(cost) = part.get("cost").and_then(|value| value.as_f64()) {
                result.cost_usd = cost;
            }
        }
    }
}

fn apply_claude_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) {
    let msg_type = obj
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    match msg_type {
        "system" => {
            let subtype = obj
                .get("subtype")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if subtype == "init" {
                result.session_id = obj
                    .get("session_id")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
            } else if subtype == "api_retry" {
                result.events.push(JsonEvent {
                    event_type: "system_retry".into(),
                    text: String::new(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
        }
        "assistant" => {
            if let Some(message) = obj.get("message").and_then(|value| value.as_object()) {
                if let Some(content) = message.get("content").and_then(|value| value.as_array()) {
                    let texts: Vec<String> = content
                        .iter()
                        .filter(|block| {
                            block.get("type").and_then(|value| value.as_str()) == Some("text")
                        })
                        .filter_map(|block| block.get("text").and_then(|value| value.as_str()))
                        .map(|text| text.to_string())
                        .collect();
                    if !texts.is_empty() {
                        result.final_text = texts.join("\n");
                        result.events.push(JsonEvent {
                            event_type: "assistant".into(),
                            text: result.final_text.clone(),
                            thinking: String::new(),
                            tool_call: None,
                            tool_result: None,
                        });
                    }
                }
                if let Some(usage) = message.get("usage").and_then(|value| value.as_object()) {
                    result.usage = usage
                        .iter()
                        .filter_map(|(key, value)| value.as_i64().map(|count| (key.clone(), count)))
                        .collect();
                }
            }
        }
        "user" => {
            if let Some(message) = obj.get("message").and_then(|value| value.as_object()) {
                if let Some(content) = message.get("content").and_then(|value| value.as_array()) {
                    for block in content {
                        if block.get("type").and_then(|value| value.as_str()) == Some("tool_result")
                        {
                            result.events.push(JsonEvent {
                                event_type: "tool_result".into(),
                                text: String::new(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: Some(ToolResult {
                                    tool_call_id: block
                                        .get("tool_use_id")
                                        .and_then(|value| value.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                    content: block
                                        .get("content")
                                        .and_then(|value| value.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                    is_error: block
                                        .get("is_error")
                                        .and_then(|value| value.as_bool())
                                        .unwrap_or(false),
                                }),
                            });
                        }
                    }
                }
            }
        }
        "stream_event" => {
            if let Some(event) = obj.get("event").and_then(|value| value.as_object()) {
                let event_type = event
                    .get("type")
                    .and_then(|value| value.as_str())
                    .unwrap_or("");
                if event_type == "content_block_delta" {
                    if let Some(delta) = event.get("delta").and_then(|value| value.as_object()) {
                        let delta_type = delta
                            .get("type")
                            .and_then(|value| value.as_str())
                            .unwrap_or("");
                        match delta_type {
                            "text_delta" => result.events.push(JsonEvent {
                                event_type: "text_delta".into(),
                                text: delta
                                    .get("text")
                                    .and_then(|value| value.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: None,
                            }),
                            "thinking_delta" => result.events.push(JsonEvent {
                                event_type: "thinking_delta".into(),
                                text: String::new(),
                                thinking: delta
                                    .get("thinking")
                                    .and_then(|value| value.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                tool_call: None,
                                tool_result: None,
                            }),
                            "input_json_delta" => result.events.push(JsonEvent {
                                event_type: "tool_input_delta".into(),
                                text: delta
                                    .get("partial_json")
                                    .and_then(|value| value.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: None,
                            }),
                            _ => {}
                        }
                    }
                } else if event_type == "content_block_start" {
                    if let Some(content_block) = event
                        .get("content_block")
                        .and_then(|value| value.as_object())
                    {
                        let block_type = content_block
                            .get("type")
                            .and_then(|value| value.as_str())
                            .unwrap_or("");
                        if block_type == "thinking" {
                            result.events.push(JsonEvent {
                                event_type: "thinking_start".into(),
                                text: String::new(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: None,
                            });
                        } else if block_type == "tool_use" {
                            result.events.push(JsonEvent {
                                event_type: "tool_use_start".into(),
                                text: String::new(),
                                thinking: String::new(),
                                tool_call: Some(ToolCall {
                                    id: content_block
                                        .get("id")
                                        .and_then(|value| value.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                    name: content_block
                                        .get("name")
                                        .and_then(|value| value.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                    arguments: String::new(),
                                }),
                                tool_result: None,
                            });
                        }
                    }
                }
            }
        }
        "tool_use" => {
            let tool_input = obj
                .get("tool_input")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            result.events.push(JsonEvent {
                event_type: "tool_use".into(),
                text: String::new(),
                thinking: String::new(),
                tool_call: Some(ToolCall {
                    id: String::new(),
                    name: obj
                        .get("tool_name")
                        .and_then(|value| value.as_str())
                        .unwrap_or("")
                        .to_string(),
                    arguments: serde_json::to_string(&tool_input).unwrap_or_default(),
                }),
                tool_result: None,
            });
        }
        "tool_result" => {
            result.events.push(JsonEvent {
                event_type: "tool_result".into(),
                text: String::new(),
                thinking: String::new(),
                tool_call: None,
                tool_result: Some(ToolResult {
                    tool_call_id: obj
                        .get("tool_use_id")
                        .and_then(|value| value.as_str())
                        .unwrap_or("")
                        .to_string(),
                    content: obj
                        .get("content")
                        .and_then(|value| value.as_str())
                        .unwrap_or("")
                        .to_string(),
                    is_error: obj
                        .get("is_error")
                        .and_then(|value| value.as_bool())
                        .unwrap_or(false),
                }),
            });
        }
        "result" => {
            let subtype = obj
                .get("subtype")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if subtype == "success" {
                result.final_text = obj
                    .get("result")
                    .and_then(|value| value.as_str())
                    .unwrap_or(&result.final_text)
                    .to_string();
                result.cost_usd = obj
                    .get("cost_usd")
                    .and_then(|value| value.as_f64())
                    .unwrap_or(0.0);
                result.duration_ms = obj
                    .get("duration_ms")
                    .and_then(|value| value.as_i64())
                    .unwrap_or(0);
                if let Some(usage) = obj.get("usage").and_then(|value| value.as_object()) {
                    result.usage = usage
                        .iter()
                        .filter_map(|(key, value)| value.as_i64().map(|count| (key.clone(), count)))
                        .collect();
                }
                result.events.push(JsonEvent {
                    event_type: "result".into(),
                    text: result.final_text.clone(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            } else if subtype == "error" {
                result.error = obj
                    .get("error")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                result.events.push(JsonEvent {
                    event_type: "error".into(),
                    text: result.error.clone(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
        }
        _ => {}
    }
}

fn apply_kimi_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) {
    let passthrough_events = [
        "TurnBegin",
        "StepBegin",
        "StepInterrupted",
        "TurnEnd",
        "StatusUpdate",
        "HookTriggered",
        "HookResolved",
        "ApprovalRequest",
        "SubagentEvent",
        "ToolCallRequest",
    ];
    let wire_type = obj
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    if passthrough_events.contains(&wire_type) {
        result.events.push(JsonEvent {
            event_type: wire_type.to_ascii_lowercase(),
            text: String::new(),
            thinking: String::new(),
            tool_call: None,
            tool_result: None,
        });
        return;
    }

    let role = obj
        .get("role")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    if role == "assistant" {
        if let Some(text) = obj.get("content").and_then(|value| value.as_str()) {
            result.final_text = text.to_string();
            result.events.push(JsonEvent {
                event_type: "assistant".into(),
                text: text.to_string(),
                thinking: String::new(),
                tool_call: None,
                tool_result: None,
            });
        } else if let Some(parts) = obj.get("content").and_then(|value| value.as_array()) {
            let mut texts = Vec::new();
            for part in parts {
                let part_type = part
                    .get("type")
                    .and_then(|value| value.as_str())
                    .unwrap_or("");
                if part_type == "text" {
                    if let Some(text) = part.get("text").and_then(|value| value.as_str()) {
                        texts.push(text.to_string());
                    }
                } else if part_type == "think" {
                    result.events.push(JsonEvent {
                        event_type: "thinking".into(),
                        text: String::new(),
                        thinking: part
                            .get("think")
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
            }
            if !texts.is_empty() {
                result.final_text = texts.join("\n");
                result.events.push(JsonEvent {
                    event_type: "assistant".into(),
                    text: result.final_text.clone(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
        }
        if let Some(tool_calls) = obj.get("tool_calls").and_then(|value| value.as_array()) {
            for tool_call in tool_calls {
                let function = tool_call
                    .get("function")
                    .and_then(|value| value.as_object());
                result.events.push(JsonEvent {
                    event_type: "tool_call".into(),
                    text: String::new(),
                    thinking: String::new(),
                    tool_call: Some(ToolCall {
                        id: tool_call
                            .get("id")
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                        name: function
                            .and_then(|f| f.get("name"))
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                        arguments: function
                            .and_then(|f| f.get("arguments"))
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                    }),
                    tool_result: None,
                });
            }
        }
    } else if role == "tool" {
        let mut texts = Vec::new();
        if let Some(parts) = obj.get("content").and_then(|value| value.as_array()) {
            for part in parts {
                if part.get("type").and_then(|value| value.as_str()) == Some("text") {
                    if let Some(text) = part.get("text").and_then(|value| value.as_str()) {
                        if !text.starts_with("<system>") {
                            texts.push(text.to_string());
                        }
                    }
                }
            }
        }
        result.events.push(JsonEvent {
            event_type: "tool_result".into(),
            text: String::new(),
            thinking: String::new(),
            tool_call: None,
            tool_result: Some(ToolResult {
                tool_call_id: obj
                    .get("tool_call_id")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string(),
                content: texts.join("\n"),
                is_error: false,
            }),
        });
    }
}

fn message_text(message: &serde_json::Value) -> String {
    if let Some(text) = message.get("content").and_then(|value| value.as_str()) {
        return text.to_string();
    }
    let Some(content) = message.get("content").and_then(|value| value.as_array()) else {
        return String::new();
    };
    content
        .iter()
        .filter(|block| block.get("type").and_then(|value| value.as_str()) == Some("text"))
        .filter_map(|block| block.get("text").and_then(|value| value.as_str()))
        .map(str::to_string)
        .collect::<Vec<_>>()
        .join("\n")
}

fn normalize_cursor_text(text: &str) -> String {
    text.trim_matches('\n').to_string()
}

fn apply_cursor_agent_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) {
    match obj
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("")
    {
        "system" => {
            if obj.get("subtype").and_then(|value| value.as_str()) == Some("init") {
                result.session_id = obj
                    .get("session_id")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
            }
        }
        "assistant" => {
            let text =
                normalize_cursor_text(&obj.get("message").map(message_text).unwrap_or_default());
            if !text.is_empty() {
                result.final_text = text.clone();
                result.events.push(JsonEvent {
                    event_type: "assistant".into(),
                    text,
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
        }
        "result" => {
            if let Some(session_id) = obj.get("session_id").and_then(|value| value.as_str()) {
                result.session_id = session_id.to_string();
            }
            if let Some(duration) = obj.get("duration_ms").and_then(|value| value.as_i64()) {
                result.duration_ms = duration;
            }
            if let Some(usage) = obj.get("usage").and_then(|value| value.as_object()) {
                result.usage = usage
                    .iter()
                    .filter_map(|(key, value)| value.as_i64().map(|number| (key.clone(), number)))
                    .collect();
            }
            let is_error = obj
                .get("is_error")
                .and_then(|value| value.as_bool())
                .unwrap_or(false);
            let subtype = obj
                .get("subtype")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if subtype == "success" && !is_error {
                let text = normalize_cursor_text(
                    obj.get("result")
                        .and_then(|value| value.as_str())
                        .unwrap_or(&result.final_text),
                );
                result.final_text = text.clone();
                if !text.is_empty() {
                    result.events.push(JsonEvent {
                        event_type: "result".into(),
                        text,
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
            } else {
                let text = obj
                    .get("error")
                    .or_else(|| obj.get("result"))
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                result.error = text.clone();
                result.events.push(JsonEvent {
                    event_type: "error".into(),
                    text,
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
        }
        _ => {}
    }
}

fn apply_codex_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) -> bool {
    match obj
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("")
    {
        "thread.started" => {
            result.session_id = obj
                .get("thread_id")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            true
        }
        "turn.started" => true,
        "turn.completed" => {
            if let Some(usage) = obj.get("usage").and_then(|value| value.as_object()) {
                result.usage = usage
                    .iter()
                    .filter_map(|(key, value)| value.as_i64().map(|count| (key.clone(), count)))
                    .collect();
            }
            true
        }
        "item.started" | "item.completed" => {
            let Some(item) = obj.get("item").and_then(|value| value.as_object()) else {
                return false;
            };
            let item_type = item
                .get("type")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if item_type == "agent_message"
                && obj.get("type").and_then(|value| value.as_str()) == Some("item.completed")
            {
                let text = item
                    .get("text")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                result.final_text = text.clone();
                result.events.push(JsonEvent {
                    event_type: "assistant".into(),
                    text,
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
                true
            } else if item_type == "command_execution" {
                let call_id = item
                    .get("id")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                let command = item
                    .get("command")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                if obj.get("type").and_then(|value| value.as_str()) == Some("item.started") {
                    result.events.push(JsonEvent {
                        event_type: "tool_use_start".into(),
                        text: String::new(),
                        thinking: String::new(),
                        tool_call: Some(ToolCall {
                            id: call_id,
                            name: "command_execution".into(),
                            arguments: serde_json::json!({ "command": command }).to_string(),
                        }),
                        tool_result: None,
                    });
                    true
                } else {
                    let status = item
                        .get("status")
                        .and_then(|value| value.as_str())
                        .unwrap_or("");
                    let exit_code = item.get("exit_code").and_then(|value| value.as_i64());
                    result.events.push(JsonEvent {
                        event_type: "tool_result".into(),
                        text: String::new(),
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: Some(ToolResult {
                            tool_call_id: call_id,
                            content: item
                                .get("aggregated_output")
                                .and_then(|value| value.as_str())
                                .unwrap_or("")
                                .to_string(),
                            is_error: exit_code.is_some_and(|code| code != 0)
                                || (!status.is_empty() && status != "completed"),
                        }),
                    });
                    true
                }
            } else {
                false
            }
        }
        _ => false,
    }
}

fn apply_gemini_stats(
    result: &mut ParsedJsonOutput,
    stats: &serde_json::Map<String, serde_json::Value>,
) {
    let usage: BTreeMap<String, i64> = stats
        .iter()
        .filter_map(|(key, value)| value.as_i64().map(|count| (key.clone(), count)))
        .collect();
    if !usage.is_empty() {
        result.usage = usage;
    }
    if let Some(duration_ms) = stats.get("duration_ms").and_then(|value| value.as_i64()) {
        result.duration_ms = duration_ms;
    }
}

fn apply_gemini_obj(result: &mut ParsedJsonOutput, obj: &serde_json::Value) -> bool {
    if let Some(session_id) = obj.get("session_id").and_then(|value| value.as_str()) {
        if !session_id.is_empty() {
            result.session_id = session_id.to_string();
        }
    }

    if let Some(response) = obj.get("response").and_then(|value| value.as_str()) {
        result.final_text = response.to_string();
        if !response.is_empty() {
            result.events.push(JsonEvent {
                event_type: "assistant".into(),
                text: response.into(),
                thinking: String::new(),
                tool_call: None,
                tool_result: None,
            });
        }
        if let Some(stats) = obj.get("stats").and_then(|value| value.as_object()) {
            apply_gemini_stats(result, stats);
        }
        return true;
    }

    match obj
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("")
    {
        "init" => true,
        "message" => {
            let role = obj
                .get("role")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if role == "assistant" {
                let text = obj
                    .get("content")
                    .and_then(|value| value.as_str())
                    .unwrap_or("");
                result.final_text.push_str(text);
                if !text.is_empty() {
                    result.events.push(JsonEvent {
                        event_type: if obj
                            .get("delta")
                            .and_then(|value| value.as_bool())
                            .unwrap_or(false)
                        {
                            "text_delta".into()
                        } else {
                            "assistant".into()
                        },
                        text: text.into(),
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
                true
            } else {
                role == "user"
            }
        }
        "result" => {
            if let Some(stats) = obj.get("stats").and_then(|value| value.as_object()) {
                apply_gemini_stats(result, stats);
            }
            let status = obj
                .get("status")
                .and_then(|value| value.as_str())
                .unwrap_or("");
            if !status.is_empty() && status != "success" {
                result.error = obj
                    .get("error")
                    .and_then(|value| value.as_str())
                    .unwrap_or(status)
                    .to_string();
                result.events.push(JsonEvent {
                    event_type: "error".into(),
                    text: result.error.clone(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            }
            true
        }
        _ => false,
    }
}

pub fn parse_opencode_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("opencode");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            let before = parser_state(&result);
            apply_opencode_obj(&mut result, &obj);
            let after = parser_state(&result);
            if before == after {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_claude_code_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("claude-code");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            let before = parser_state(&result);
            apply_claude_obj(&mut result, &obj);
            let after = parser_state(&result);
            if before == after {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_kimi_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("kimi");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            let before = parser_state(&result);
            apply_kimi_obj(&mut result, &obj);
            let after = parser_state(&result);
            if before == after {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_cursor_agent_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("cursor-agent");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            let before = parser_state(&result);
            apply_cursor_agent_obj(&mut result, &obj);
            let after = parser_state(&result);
            if before == after {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_codex_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("codex");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            if !apply_codex_obj(&mut result, &obj) {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_gemini_json(raw: &str) -> ParsedJsonOutput {
    let mut result = new_output("gemini");
    for line in raw.lines() {
        if let Some(obj) = parse_json_line(line) {
            if !apply_gemini_obj(&mut result, &obj) {
                result.unknown_json_lines.push(line.trim().to_string());
            }
        }
    }
    result
}

pub fn parse_json_output(raw: &str, schema: &str) -> ParsedJsonOutput {
    match schema {
        "opencode" => parse_opencode_json(raw),
        "claude-code" => parse_claude_code_json(raw),
        "kimi" => parse_kimi_json(raw),
        "cursor-agent" => parse_cursor_agent_json(raw),
        "codex" => parse_codex_json(raw),
        "gemini" => parse_gemini_json(raw),
        _ => ParsedJsonOutput {
            schema_name: schema.into(),
            events: Vec::new(),
            final_text: String::new(),
            session_id: String::new(),
            error: format!("unknown schema: {schema}"),
            usage: BTreeMap::new(),
            cost_usd: 0.0,
            duration_ms: 0,
            unknown_json_lines: Vec::new(),
        },
    }
}

fn truncate_to_char_limit(text: &str, max_chars: usize) -> Option<String> {
    text.char_indices()
        .nth(max_chars)
        .map(|(index, _)| text[..index].to_string())
}

fn summarize_text(text: &str, max_lines: usize, max_chars: usize) -> String {
    let lines: Vec<&str> = text.trim().lines().collect();
    if lines.is_empty() {
        return String::new();
    }
    let mut clipped = lines
        .into_iter()
        .take(max_lines)
        .collect::<Vec<_>>()
        .join("\n");
    let mut truncated = text.trim().lines().count() > max_lines;
    if let Some(safe_clipped) = truncate_to_char_limit(&clipped, max_chars) {
        clipped = safe_clipped;
        clipped = clipped.trim_end().to_string();
        truncated = true;
    }
    if truncated {
        clipped.push_str(" …");
    }
    clipped
}

fn parse_tool_arguments(arguments: &str) -> Option<serde_json::Map<String, serde_json::Value>> {
    let value: serde_json::Value = serde_json::from_str(arguments).ok()?;
    value.as_object().cloned()
}

fn bash_command_preview(tool_call: &ToolCall) -> Option<String> {
    let args = parse_tool_arguments(&tool_call.arguments)?;
    for key in ["command", "cmd", "bash_command", "script"] {
        if let Some(value) = args.get(key).and_then(|value| value.as_str()) {
            let mut preview = value.trim().to_string();
            if preview.is_empty() {
                continue;
            }
            if let Some(safe_preview) = truncate_to_char_limit(&preview, 400) {
                preview = safe_preview.trim_end().to_string() + " …";
            }
            return Some(preview);
        }
    }
    None
}

fn tool_preview(tool_name: &str, text: &str) -> String {
    match tool_name.to_ascii_lowercase().as_str() {
        "read" | "write" | "edit" | "multiedit" | "read_file" | "write_file" | "edit_file" => {
            String::new()
        }
        _ => summarize_text(text, 8, 400),
    }
}

pub fn resolve_human_tty(tty: bool, force_color: Option<&str>, no_color: Option<&str>) -> bool {
    if force_color.is_some_and(|value| !value.is_empty()) {
        return true;
    }
    if no_color.is_some_and(|value| !value.is_empty()) {
        return false;
    }
    tty
}

fn style(text: &str, code: &str, tty: bool) -> String {
    if tty {
        format!("\x1b[{code}m{text}\x1b[0m")
    } else {
        text.to_string()
    }
}

pub struct FormattedRenderer {
    show_thinking: bool,
    tty: bool,
    seen_final_texts: BTreeSet<String>,
    tool_calls_by_id: BTreeMap<String, ToolCall>,
    pending_tool_call: Option<ToolCall>,
    streamed_assistant_buffer: String,
    plain_text_tool_work: bool,
}

impl FormattedRenderer {
    pub fn new(show_thinking: bool, tty: bool) -> Self {
        Self {
            show_thinking,
            tty,
            seen_final_texts: BTreeSet::new(),
            tool_calls_by_id: BTreeMap::new(),
            pending_tool_call: None,
            streamed_assistant_buffer: String::new(),
            plain_text_tool_work: false,
        }
    }

    pub fn render_output(&mut self, output: &ParsedJsonOutput) -> String {
        output
            .events
            .iter()
            .filter_map(|event| self.render_event(event))
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn render_event(&mut self, event: &JsonEvent) -> Option<String> {
        match event.event_type.as_str() {
            "text_delta" if !event.text.is_empty() => {
                self.streamed_assistant_buffer.push_str(&event.text);
                Some(self.render_message("assistant", &event.text))
            }
            "text" | "assistant" if !event.text.is_empty() => {
                if !self.streamed_assistant_buffer.is_empty()
                    && event.text == self.streamed_assistant_buffer
                {
                    self.seen_final_texts.insert(event.text.clone());
                    self.streamed_assistant_buffer.clear();
                    None
                } else {
                    self.streamed_assistant_buffer.clear();
                    Some(self.render_message("assistant", &event.text))
                }
            }
            "result" if !event.text.is_empty() => {
                if !self.streamed_assistant_buffer.is_empty()
                    && event.text == self.streamed_assistant_buffer
                {
                    self.seen_final_texts.insert(event.text.clone());
                    self.streamed_assistant_buffer.clear();
                    None
                } else if self.seen_final_texts.contains(&event.text) {
                    None
                } else {
                    self.streamed_assistant_buffer.clear();
                    Some(self.render_message("success", &event.text))
                }
            }
            "thinking" | "thinking_delta" if !event.thinking.is_empty() && self.show_thinking => {
                Some(self.render_message("thinking", &event.thinking))
            }
            "tool_use" | "tool_use_start" | "tool_call" => {
                if let Some(tool_call) = &event.tool_call {
                    self.streamed_assistant_buffer.clear();
                    if !tool_call.id.is_empty() {
                        self.tool_calls_by_id
                            .insert(tool_call.id.clone(), tool_call.clone());
                    }
                    self.pending_tool_call = Some(tool_call.clone());
                    self.plain_text_tool_work = true;
                    Some(self.render_tool_start(tool_call))
                } else {
                    None
                }
            }
            "tool_input_delta" if !event.text.is_empty() => {
                if let Some(tool_call) = &mut self.pending_tool_call {
                    tool_call.arguments.push_str(&event.text);
                    if !tool_call.id.is_empty() {
                        self.tool_calls_by_id
                            .insert(tool_call.id.clone(), tool_call.clone());
                    }
                }
                None
            }
            "tool_result" => event.tool_result.as_ref().map(|tool_result| {
                self.streamed_assistant_buffer.clear();
                self.render_tool_result(tool_result)
            }),
            "error" if !event.text.is_empty() => {
                self.streamed_assistant_buffer.clear();
                Some(self.render_message("error", &event.text))
            }
            _ => None,
        }
    }

    fn render_message(&mut self, kind: &str, text: &str) -> String {
        if matches!(kind, "assistant" | "success") {
            self.seen_final_texts.insert(text.to_string());
        }
        let prefix = match kind {
            "assistant" => renderer_prefix(
                "💬",
                "[assistant]",
                "96",
                self.tty,
                self.plain_text_tool_work,
            ),
            "thinking" => renderer_prefix(
                "🧠",
                "[thinking]",
                "2;35",
                self.tty,
                self.plain_text_tool_work,
            ),
            "success" => renderer_prefix("✅", "[ok]", "92", self.tty, self.plain_text_tool_work),
            _ => renderer_prefix("❌", "[error]", "91", self.tty, self.plain_text_tool_work),
        };
        with_prefix(&prefix, text)
    }

    fn render_tool_start(&self, tool_call: &ToolCall) -> String {
        let prefix = prefix("🛠️", "[tool:start]", "94", self.tty);
        let mut detail = tool_call.name.clone();
        if let Some(preview) = bash_command_preview(tool_call) {
            detail.push_str(": ");
            detail.push_str(&preview);
        }
        with_prefix(&prefix, &detail)
    }

    fn render_tool_result(&self, tool_result: &ToolResult) -> String {
        let prefix = prefix("📎", "[tool:result]", "36", self.tty);
        let tool_call = self
            .tool_calls_by_id
            .get(&tool_result.tool_call_id)
            .or(self.pending_tool_call.as_ref());
        let tool_name = tool_call
            .map(|tool_call| tool_call.name.clone())
            .unwrap_or_else(|| "tool".into());
        let mut summary = format!(
            "{} ({})",
            tool_name,
            if tool_result.is_error { "error" } else { "ok" }
        );
        if let Some(tool_call) = tool_call {
            if let Some(preview) = bash_command_preview(tool_call) {
                summary.push_str(": ");
                summary.push_str(&preview);
            }
        }
        let preview = tool_preview(&tool_name, &tool_result.content);
        if !preview.is_empty() {
            summary.push('\n');
            summary.push_str(&preview);
        }
        with_prefix(&prefix, &summary)
    }
}

fn prefix(emoji: &str, plain: &str, color_code: &str, tty: bool) -> String {
    if tty {
        style(emoji, color_code, true)
    } else {
        plain.to_string()
    }
}

fn renderer_prefix(
    emoji: &str,
    plain: &str,
    color_code: &str,
    tty: bool,
    plain_text_tool_work: bool,
) -> String {
    if tty {
        return style(emoji, color_code, true);
    }
    if plain_text_tool_work && matches!(plain, "[assistant]" | "[thinking]" | "[ok]" | "[error]") {
        return plain.to_string();
    }
    plain.to_string()
}

fn with_prefix(prefix: &str, text: &str) -> String {
    text.lines()
        .map(|line| {
            if line.is_empty() {
                prefix.to_string()
            } else {
                format!("{prefix} {line}")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

pub struct StructuredStreamProcessor {
    schema: String,
    renderer: FormattedRenderer,
    output: ParsedJsonOutput,
    buffer: String,
    unknown_json_lines: Vec<String>,
}

impl StructuredStreamProcessor {
    pub fn new(schema: &str, renderer: FormattedRenderer) -> Self {
        Self {
            schema: schema.into(),
            renderer,
            output: new_output(schema),
            buffer: String::new(),
            unknown_json_lines: Vec::new(),
        }
    }

    pub fn output(&self) -> &ParsedJsonOutput {
        &self.output
    }

    pub fn feed(&mut self, chunk: &str) -> String {
        self.buffer.push_str(chunk);
        let mut rendered = Vec::new();
        while let Some(index) = self.buffer.find('\n') {
            let line = self.buffer[..index].to_string();
            self.buffer = self.buffer[index + 1..].to_string();
            if let Some(obj) = parse_json_line(&line) {
                let before = parser_state(&self.output);
                let event_count = self.output.events.len();
                let recognized = self.apply(&obj);
                let after = parser_state(&self.output);
                if before == after && !recognized {
                    self.unknown_json_lines.push(line.trim().to_string());
                }
                for event in &self.output.events[event_count..] {
                    if let Some(text) = self.renderer.render_event(event) {
                        rendered.push(text);
                    }
                }
            }
        }
        rendered.join("\n")
    }

    pub fn finish(&mut self) -> String {
        if self.buffer.trim().is_empty() {
            return String::new();
        }
        let line = std::mem::take(&mut self.buffer);
        if let Some(obj) = parse_json_line(&line) {
            let before = parser_state(&self.output);
            let event_count = self.output.events.len();
            let recognized = self.apply(&obj);
            let after = parser_state(&self.output);
            if before == after && !recognized {
                self.unknown_json_lines.push(line.trim().to_string());
            }
            return self.output.events[event_count..]
                .iter()
                .filter_map(|event| self.renderer.render_event(event))
                .collect::<Vec<_>>()
                .join("\n");
        }
        String::new()
    }

    pub fn take_unknown_json_lines(&mut self) -> Vec<String> {
        std::mem::take(&mut self.unknown_json_lines)
    }

    fn apply(&mut self, obj: &serde_json::Value) -> bool {
        match self.schema.as_str() {
            "opencode" => {
                apply_opencode_obj(&mut self.output, obj);
                false
            }
            "claude-code" => {
                apply_claude_obj(&mut self.output, obj);
                false
            }
            "kimi" => {
                apply_kimi_obj(&mut self.output, obj);
                false
            }
            "cursor-agent" => {
                apply_cursor_agent_obj(&mut self.output, obj);
                false
            }
            "codex" => apply_codex_obj(&mut self.output, obj),
            "gemini" => apply_gemini_obj(&mut self.output, obj),
            _ => false,
        }
    }
}

pub fn render_parsed(output: &ParsedJsonOutput, show_thinking: bool, tty: bool) -> String {
    let mut renderer = FormattedRenderer::new(show_thinking, tty);
    let rendered = renderer.render_output(output);
    if rendered.is_empty() {
        output.final_text.clone()
    } else {
        rendered
    }
}

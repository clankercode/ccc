use std::collections::HashMap;

pub struct TextContent {
    pub text: String,
}

pub struct ThinkingContent {
    pub thinking: String,
}

pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

pub struct ToolResult {
    pub tool_call_id: String,
    pub content: String,
    pub is_error: bool,
}

pub struct JsonEvent {
    pub event_type: String,
    pub text: String,
    pub thinking: String,
    pub tool_call: Option<ToolCall>,
    pub tool_result: Option<ToolResult>,
}

pub struct ParsedJsonOutput {
    pub schema_name: String,
    pub events: Vec<JsonEvent>,
    pub final_text: String,
    pub session_id: String,
    pub error: String,
    pub usage: HashMap<String, i64>,
    pub cost_usd: f64,
    pub duration_ms: i64,
}

pub fn parse_opencode_json(raw: &str) -> ParsedJsonOutput {
    let mut result = ParsedJsonOutput {
        schema_name: "opencode".into(),
        events: Vec::new(),
        final_text: String::new(),
        session_id: String::new(),
        error: String::new(),
        usage: HashMap::new(),
        cost_usd: 0.0,
        duration_ms: 0,
    };
    for line in raw.trim().lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let obj: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if let Some(text) = obj.get("response").and_then(|v| v.as_str()) {
            let text = text.to_string();
            result.final_text = text.clone();
            result.events.push(JsonEvent {
                event_type: "text".into(),
                text,
                thinking: String::new(),
                tool_call: None,
                tool_result: None,
            });
        } else if let Some(err) = obj.get("error").and_then(|v| v.as_str()) {
            result.error = err.to_string();
            result.events.push(JsonEvent {
                event_type: "error".into(),
                text: err.to_string(),
                thinking: String::new(),
                tool_call: None,
                tool_result: None,
            });
        }
    }
    result
}

pub fn parse_claude_code_json(raw: &str) -> ParsedJsonOutput {
    let mut result = ParsedJsonOutput {
        schema_name: "claude-code".into(),
        events: Vec::new(),
        final_text: String::new(),
        session_id: String::new(),
        error: String::new(),
        usage: HashMap::new(),
        cost_usd: 0.0,
        duration_ms: 0,
    };
    for line in raw.trim().lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let obj: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let msg_type = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");

        match msg_type {
            "system" => {
                let sub = obj.get("subtype").and_then(|v| v.as_str()).unwrap_or("");
                if sub == "init" {
                    result.session_id = obj
                        .get("session_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                } else if sub == "api_retry" {
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
                let message = obj
                    .get("message")
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);
                let content = message.get("content").and_then(|v| v.as_array());
                let mut texts: Vec<String> = Vec::new();
                if let Some(blocks) = content {
                    for block in blocks {
                        if block.get("type").and_then(|v| v.as_str()) == Some("text") {
                            if let Some(t) = block.get("text").and_then(|v| v.as_str()) {
                                texts.push(t.to_string());
                            }
                        }
                    }
                }
                if !texts.is_empty() {
                    let text = texts.join("\n");
                    result.final_text = text.clone();
                    result.events.push(JsonEvent {
                        event_type: "assistant".into(),
                        text,
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
                if let Some(usage) = message.get("usage").and_then(|v| v.as_object()) {
                    result.usage = usage
                        .iter()
                        .filter_map(|(k, v)| v.as_i64().map(|i| (k.clone(), i)))
                        .collect();
                }
            }
            "stream_event" => {
                let event = obj.get("event").cloned().unwrap_or(serde_json::Value::Null);
                let event_type = event.get("type").and_then(|v| v.as_str()).unwrap_or("");
                if event_type == "content_block_delta" {
                    let delta = event
                        .get("delta")
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    let delta_type = delta.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    match delta_type {
                        "text_delta" => {
                            result.events.push(JsonEvent {
                                event_type: "text_delta".into(),
                                text: delta
                                    .get("text")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: None,
                            });
                        }
                        "thinking_delta" => {
                            result.events.push(JsonEvent {
                                event_type: "thinking_delta".into(),
                                text: String::new(),
                                thinking: delta
                                    .get("thinking")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                tool_call: None,
                                tool_result: None,
                            });
                        }
                        "input_json_delta" => {
                            result.events.push(JsonEvent {
                                event_type: "tool_input_delta".into(),
                                text: delta
                                    .get("partial_json")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                thinking: String::new(),
                                tool_call: None,
                                tool_result: None,
                            });
                        }
                        _ => {}
                    }
                } else if event_type == "content_block_start" {
                    let cb = event
                        .get("content_block")
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    let cb_type = cb.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    if cb_type == "thinking" {
                        result.events.push(JsonEvent {
                            event_type: "thinking_start".into(),
                            text: String::new(),
                            thinking: String::new(),
                            tool_call: None,
                            tool_result: None,
                        });
                    } else if cb_type == "tool_use" {
                        result.events.push(JsonEvent {
                            event_type: "tool_use_start".into(),
                            text: String::new(),
                            thinking: String::new(),
                            tool_call: Some(ToolCall {
                                id: cb
                                    .get("id")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                name: cb
                                    .get("name")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                arguments: String::new(),
                            }),
                            tool_result: None,
                        });
                    }
                }
            }
            "tool_use" => {
                let tc = ToolCall {
                    id: String::new(),
                    name: obj
                        .get("tool_name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    arguments: serde_json::to_string(
                        &obj.get("tool_input")
                            .cloned()
                            .unwrap_or(serde_json::Value::Null),
                    )
                    .unwrap_or_default(),
                };
                result.events.push(JsonEvent {
                    event_type: "tool_use".into(),
                    text: String::new(),
                    thinking: String::new(),
                    tool_call: Some(tc),
                    tool_result: None,
                });
            }
            "tool_result" => {
                let tr = ToolResult {
                    tool_call_id: obj
                        .get("tool_use_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    content: obj
                        .get("content")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    is_error: obj
                        .get("is_error")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                };
                result.events.push(JsonEvent {
                    event_type: "tool_result".into(),
                    text: String::new(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: Some(tr),
                });
            }
            "result" => {
                let sub = obj.get("subtype").and_then(|v| v.as_str()).unwrap_or("");
                if sub == "success" {
                    let text = obj
                        .get("result")
                        .and_then(|v| v.as_str())
                        .unwrap_or(&result.final_text)
                        .to_string();
                    result.final_text = text.clone();
                    result.cost_usd = obj.get("cost_usd").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    result.duration_ms =
                        obj.get("duration_ms").and_then(|v| v.as_i64()).unwrap_or(0);
                    if let Some(usage) = obj.get("usage").and_then(|v| v.as_object()) {
                        result.usage = usage
                            .iter()
                            .filter_map(|(k, v)| v.as_i64().map(|i| (k.clone(), i)))
                            .collect();
                    }
                    result.events.push(JsonEvent {
                        event_type: "result".into(),
                        text,
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                } else if sub == "error" {
                    let err = obj
                        .get("error")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    result.error = err.clone();
                    result.events.push(JsonEvent {
                        event_type: "error".into(),
                        text: err,
                        thinking: String::new(),
                        tool_call: None,
                        tool_result: None,
                    });
                }
            }
            _ => {}
        }
    }
    result
}

pub fn parse_kimi_json(raw: &str) -> ParsedJsonOutput {
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
    let mut result = ParsedJsonOutput {
        schema_name: "kimi".into(),
        events: Vec::new(),
        final_text: String::new(),
        session_id: String::new(),
        error: String::new(),
        usage: HashMap::new(),
        cost_usd: 0.0,
        duration_ms: 0,
    };
    for line in raw.trim().lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let obj: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let wire_type = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if passthrough_events.contains(&wire_type) {
            result.events.push(JsonEvent {
                event_type: wire_type.to_lowercase(),
                text: String::new(),
                thinking: String::new(),
                tool_call: None,
                tool_result: None,
            });
            continue;
        }

        let role = obj.get("role").and_then(|v| v.as_str()).unwrap_or("");
        if role == "assistant" {
            let content_val = obj
                .get("content")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let tool_calls = obj.get("tool_calls").and_then(|v| v.as_array());

            if let Some(text) = content_val.as_str() {
                result.final_text = text.to_string();
                result.events.push(JsonEvent {
                    event_type: "assistant".into(),
                    text: text.to_string(),
                    thinking: String::new(),
                    tool_call: None,
                    tool_result: None,
                });
            } else if let Some(parts) = content_val.as_array() {
                let mut texts: Vec<String> = Vec::new();
                for part in parts {
                    let part_type = part.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    if part_type == "text" {
                        if let Some(t) = part.get("text").and_then(|v| v.as_str()) {
                            texts.push(t.to_string());
                        }
                    } else if part_type == "think" {
                        result.events.push(JsonEvent {
                            event_type: "thinking".into(),
                            text: String::new(),
                            thinking: part
                                .get("think")
                                .and_then(|v| v.as_str())
                                .unwrap_or("")
                                .to_string(),
                            tool_call: None,
                            tool_result: None,
                        });
                    }
                }
                if !texts.is_empty() {
                    let text = texts.join("\n");
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

            if let Some(tc_list) = tool_calls {
                for tc_data in tc_list {
                    let fn_obj = tc_data
                        .get("function")
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    let tc = ToolCall {
                        id: tc_data
                            .get("id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        name: fn_obj
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        arguments: fn_obj
                            .get("arguments")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                    };
                    result.events.push(JsonEvent {
                        event_type: "tool_call".into(),
                        text: String::new(),
                        thinking: String::new(),
                        tool_call: Some(tc),
                        tool_result: None,
                    });
                }
            }
        } else if role == "tool" {
            let content_val = obj
                .get("content")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let mut texts: Vec<String> = Vec::new();
            if let Some(parts) = content_val.as_array() {
                for part in parts {
                    if part.get("type").and_then(|v| v.as_str()) == Some("text") {
                        if let Some(t) = part.get("text").and_then(|v| v.as_str()) {
                            if !t.starts_with("<system>") {
                                texts.push(t.to_string());
                            }
                        }
                    }
                }
            }
            let tr = ToolResult {
                tool_call_id: obj
                    .get("tool_call_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
                content: texts.join("\n"),
                is_error: false,
            };
            result.events.push(JsonEvent {
                event_type: "tool_result".into(),
                text: String::new(),
                thinking: String::new(),
                tool_call: None,
                tool_result: Some(tr),
            });
        }
    }
    result
}

pub fn parse_json_output(raw: &str, schema: &str) -> ParsedJsonOutput {
    match schema {
        "opencode" => parse_opencode_json(raw),
        "claude-code" => parse_claude_code_json(raw),
        "kimi" => parse_kimi_json(raw),
        _ => ParsedJsonOutput {
            schema_name: schema.into(),
            events: Vec::new(),
            final_text: String::new(),
            session_id: String::new(),
            error: format!("unknown schema: {}", schema),
            usage: HashMap::new(),
            cost_usd: 0.0,
            duration_ms: 0,
        },
    }
}

pub fn render_parsed(output: &ParsedJsonOutput) -> String {
    let mut parts: Vec<String> = Vec::new();
    for event in &output.events {
        match event.event_type.as_str() {
            "text" | "assistant" | "result" => {
                if !event.text.is_empty() {
                    parts.push(event.text.clone());
                }
            }
            "thinking_delta" | "thinking" => {
                if !event.thinking.is_empty() {
                    parts.push(format!("[thinking] {}", event.thinking));
                }
            }
            "tool_use" => {
                if let Some(tc) = &event.tool_call {
                    parts.push(format!("[tool] {}", tc.name));
                }
            }
            "tool_result" => {
                if let Some(tr) = &event.tool_result {
                    parts.push(format!("[tool_result] {}", tr.content));
                }
            }
            "error" => {
                if !event.text.is_empty() {
                    parts.push(format!("[error] {}", event.text));
                }
            }
            _ => {}
        }
    }
    if parts.is_empty() {
        output.final_text.clone()
    } else {
        parts.join("\n")
    }
}

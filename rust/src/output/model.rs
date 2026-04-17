use std::collections::BTreeMap;

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
pub enum Event {
    Text(String),
    Thinking(String),
    ToolCall(ToolCall),
    ToolResult(ToolResult),
    Error(String),
    RawUnknownJson(String),
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Usage {
    pub counts: BTreeMap<String, i64>,
    pub cost_usd: f64,
    pub duration_ms: i64,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Transcript {
    pub events: Vec<Event>,
    pub final_text: String,
    pub session_id: Option<String>,
    pub usage: Usage,
    pub error: Option<String>,
    pub unknown_json_lines: Vec<String>,
}

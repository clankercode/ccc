#pragma once

#include <map>
#include <optional>
#include <string>
#include <vector>

struct ToolCall {
    std::string id;
    std::string name;
    std::string arguments;
};

struct ToolResult {
    std::string tool_call_id;
    std::string content;
    bool is_error = false;
};

struct JsonEvent {
    std::string event_type;
    std::string text;
    std::string thinking;
    std::optional<ToolCall> tool_call;
    std::optional<ToolResult> tool_result;
};

struct ParsedJsonOutput {
    std::string schema_name;
    std::vector<JsonEvent> events;
    std::string final_text;
    std::string session_id;
    std::string error;
    std::map<std::string, int> usage;
    double cost_usd = 0.0;
    int duration_ms = 0;
};

ParsedJsonOutput parse_opencode_json(const std::string& raw_stdout);
ParsedJsonOutput parse_claude_code_json(const std::string& raw_stdout);
ParsedJsonOutput parse_kimi_json(const std::string& raw_stdout);
ParsedJsonOutput parse_json_output(const std::string& raw_stdout, const std::string& schema);
std::string render_parsed(const ParsedJsonOutput& output);

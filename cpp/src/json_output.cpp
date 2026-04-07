#include <ccc/json_output.hpp>

#include <sstream>
#include <algorithm>

namespace {

std::vector<std::string> split_lines(const std::string& s) {
    std::vector<std::string> lines;
    std::istringstream iss(s);
    std::string line;
    while (std::getline(iss, line)) {
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        size_t end = line.find_last_not_of(" \t\r\n");
        lines.push_back(line.substr(start, end - start + 1));
    }
    return lines;
}

bool parse_bool(const std::string& s) {
    return s == "true";
}

double parse_double(const std::string& s) {
    try { return std::stod(s); } catch (...) { return 0.0; }
}

int parse_int(const std::string& s) {
    try { return std::stoi(s); } catch (...) { return 0; }
}

std::string extract_string(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    size_t pos = 0;
    while ((pos = json.find(search, pos)) != std::string::npos) {
        size_t after = pos + search.size();
        while (after < json.size() && (json[after] == ' ' || json[after] == '\t')) after++;
        if (after < json.size() && json[after] == ':') {
            after++;
            while (after < json.size() && (json[after] == ' ' || json[after] == '\t')) after++;
            if (after >= json.size() || json[after] != '"') return "";
            size_t end = after + 1;
            while (end < json.size()) {
                if (json[end] == '\\' && end + 1 < json.size()) { end += 2; continue; }
                if (json[end] == '"') break;
                end++;
            }
            std::string val = json.substr(after + 1, end - after - 1);
            std::string result;
            for (size_t i = 0; i < val.size(); i++) {
                if (val[i] == '\\' && i + 1 < val.size()) {
                    switch (val[i + 1]) {
                        case '"': result += '"'; break;
                        case '\\': result += '\\'; break;
                        case 'n': result += '\n'; break;
                        case 't': result += '\t'; break;
                        case '/': result += '/'; break;
                        default: result += val[i + 1]; break;
                    }
                    i++;
                } else {
                    result += val[i];
                }
            }
            return result;
        }
        pos = after;
    }
    return "";
}

std::string extract_raw_value(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    size_t pos = 0;
    while ((pos = json.find(search, pos)) != std::string::npos) {
        size_t after = pos + search.size();
        while (after < json.size() && (json[after] == ' ' || json[after] == '\t')) after++;
        if (after < json.size() && json[after] == ':') {
            after++;
            while (after < json.size() && (json[after] == ' ' || json[after] == '\t')) after++;
            if (after >= json.size()) return "";
            if (json[after] == '"') {
                size_t end = after + 1;
                while (end < json.size()) {
                    if (json[end] == '\\' && end + 1 < json.size()) { end += 2; continue; }
                    if (json[end] == '"') break;
                    end++;
                }
                return json.substr(after, end - after + 1);
            }
            if (json[after] == '{') {
                int depth = 0;
                size_t end = after;
                while (end < json.size()) {
                    if (json[end] == '{') depth++;
                    else if (json[end] == '}') { depth--; if (depth == 0) break; }
                    end++;
                }
                return json.substr(after, end - after + 1);
            }
            if (json[after] == '[') {
                int depth = 0;
                size_t end = after;
                while (end < json.size()) {
                    if (json[end] == '[') depth++;
                    else if (json[end] == ']') { depth--; if (depth == 0) break; }
                    end++;
                }
                return json.substr(after, end - after + 1);
            }
            size_t end = json.find_first_of(",}]", after);
            if (end == std::string::npos) return json.substr(after);
            return json.substr(after, end - after);
        }
        pos = after;
    }
    return "";
}

bool has_key(const std::string& json, const std::string& key) {
    return json.find("\"" + key + "\"") != std::string::npos;
}

std::string to_lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
    return s;
}

std::vector<std::string> extract_array_strings(const std::string& json, const std::string& key) {
    std::vector<std::string> result;
    std::string arr = extract_raw_value(json, key);
    if (arr.empty() || arr[0] != '[') return result;
    size_t pos = 1;
    while (pos < arr.size()) {
        while (pos < arr.size() && (arr[pos] == ' ' || arr[pos] == '\t' || arr[pos] == ',')) pos++;
        if (pos >= arr.size() || arr[pos] == ']') break;
        if (arr[pos] == '"') {
            size_t end = pos + 1;
            while (end < arr.size()) {
                if (arr[end] == '\\' && end + 1 < arr.size()) { end += 2; continue; }
                if (arr[end] == '"') break;
                end++;
            }
            std::string val = arr.substr(pos + 1, end - pos - 1);
            std::string unesc;
            for (size_t i = 0; i < val.size(); i++) {
                if (val[i] == '\\' && i + 1 < val.size()) {
                    switch (val[i+1]) {
                        case '"': unesc += '"'; break;
                        case '\\': unesc += '\\'; break;
                        case 'n': unesc += '\n'; break;
                        default: unesc += val[i+1]; break;
                    }
                    i++;
                } else unesc += val[i];
            }
            result.push_back(unesc);
            pos = end + 1;
        } else {
            break;
        }
    }
    return result;
}

struct ContentBlock {
    std::string type;
    std::string text;
    std::string think;
    std::string id;
    std::string name;
};

std::vector<ContentBlock> extract_content_blocks(const std::string& parent_json, const std::string& key) {
    std::vector<ContentBlock> blocks;
    std::string arr = extract_raw_value(parent_json, key);
    if (arr.empty() || arr[0] != '[') return blocks;

    size_t pos = 1;
    while (pos < arr.size()) {
        while (pos < arr.size() && (arr[pos] == ' ' || arr[pos] == '\t' || arr[pos] == ',' || arr[pos] == '\n' || arr[pos] == '\r')) pos++;
        if (pos >= arr.size() || arr[pos] == ']') break;
        if (arr[pos] == '{') {
            int depth = 0;
            size_t start = pos;
            while (pos < arr.size()) {
                if (arr[pos] == '{') depth++;
                else if (arr[pos] == '}') { depth--; if (depth == 0) break; }
                pos++;
            }
            std::string obj = arr.substr(start, pos - start + 1);
            ContentBlock cb;
            cb.type = extract_string(obj, "type");
            cb.text = extract_string(obj, "text");
            cb.think = extract_string(obj, "think");
            cb.id = extract_string(obj, "id");
            cb.name = extract_string(obj, "name");
            blocks.push_back(cb);
            pos++;
        } else {
            pos++;
        }
    }
    return blocks;
}

std::string extract_subobject(const std::string& json, const std::string& key) {
    return extract_raw_value(json, key);
}

}

ParsedJsonOutput parse_opencode_json(const std::string& raw_stdout) {
    ParsedJsonOutput result;
    result.schema_name = "opencode";
    auto lines = split_lines(raw_stdout);
    for (const auto& line : lines) {
        if (line.empty() || line[0] != '{') continue;
        if (has_key(line, "response")) {
            std::string text = extract_string(line, "response");
            result.final_text = text;
            result.events.push_back(JsonEvent{"text", text, "", {}, {}});
        } else if (has_key(line, "error")) {
            std::string err = extract_string(line, "error");
            result.error = err;
            result.events.push_back(JsonEvent{"error", err, "", {}, {}});
        }
    }
    return result;
}

ParsedJsonOutput parse_claude_code_json(const std::string& raw_stdout) {
    ParsedJsonOutput result;
    result.schema_name = "claude-code";
    auto lines = split_lines(raw_stdout);

    for (const auto& line : lines) {
        if (line.empty() || line[0] != '{') continue;
        std::string msg_type = extract_string(line, "type");

        if (msg_type == "system") {
            std::string sub = extract_string(line, "subtype");
            if (sub == "init") {
                result.session_id = extract_string(line, "session_id");
            } else if (sub == "api_retry") {
                result.events.push_back(JsonEvent{"system_retry", "", "", {}, {}});
            }
        } else if (msg_type == "assistant") {
            std::string message = extract_subobject(line, "message");
            auto blocks = extract_content_blocks(message, "content");
            std::vector<std::string> texts;
            for (auto& b : blocks) {
                if (b.type == "text") texts.push_back(b.text);
            }
            if (!texts.empty()) {
                std::string text;
                for (size_t i = 0; i < texts.size(); i++) {
                    if (i > 0) text += "\n";
                    text += texts[i];
                }
                result.final_text = text;
                result.events.push_back(JsonEvent{"assistant", text, "", {}, {}});
            }
            std::string usage_obj = extract_subobject(message, "usage");
            if (!usage_obj.empty()) {
                if (has_key(usage_obj, "input_tokens"))
                    result.usage["input_tokens"] = parse_int(extract_raw_value(usage_obj, "input_tokens"));
                if (has_key(usage_obj, "output_tokens"))
                    result.usage["output_tokens"] = parse_int(extract_raw_value(usage_obj, "output_tokens"));
            }
        } else if (msg_type == "stream_event") {
            std::string event = extract_subobject(line, "event");
            std::string event_type = extract_string(event, "type");
            if (event_type == "content_block_delta") {
                std::string delta = extract_subobject(event, "delta");
                std::string delta_type = extract_string(delta, "type");
                if (delta_type == "text_delta") {
                    result.events.push_back(JsonEvent{"text_delta", extract_string(delta, "text"), "", {}, {}});
                } else if (delta_type == "thinking_delta") {
                    result.events.push_back(JsonEvent{"thinking_delta", "", extract_string(delta, "thinking"), {}, {}});
                } else if (delta_type == "input_json_delta") {
                    result.events.push_back(JsonEvent{"tool_input_delta", extract_string(delta, "partial_json"), "", {}, {}});
                }
            } else if (event_type == "content_block_start") {
                std::string cb = extract_subobject(event, "content_block");
                std::string cb_type = extract_string(cb, "type");
                if (cb_type == "thinking") {
                    result.events.push_back(JsonEvent{"thinking_start", "", "", {}, {}});
                } else if (cb_type == "tool_use") {
                    ToolCall tc{extract_string(cb, "id"), extract_string(cb, "name"), ""};
                    result.events.push_back(JsonEvent{"tool_use_start", "", "", tc, {}});
                }
            }
        } else if (msg_type == "tool_use") {
            std::string tool_input = extract_subobject(line, "tool_input");
            ToolCall tc{"", extract_string(line, "tool_name"), tool_input};
            result.events.push_back(JsonEvent{"tool_use", "", "", tc, {}});
        } else if (msg_type == "tool_result") {
            ToolResult tr{extract_string(line, "tool_use_id"), extract_string(line, "content"),
                          parse_bool(extract_raw_value(line, "is_error"))};
            result.events.push_back(JsonEvent{"tool_result", "", "", {}, tr});
        } else if (msg_type == "result") {
            std::string sub = extract_string(line, "subtype");
            if (sub == "success") {
                std::string res = extract_string(line, "result");
                result.final_text = res.empty() ? result.final_text : res;
                result.cost_usd = has_key(line, "cost_usd") ? parse_double(extract_raw_value(line, "cost_usd")) : result.cost_usd;
                result.duration_ms = has_key(line, "duration_ms") ? parse_int(extract_raw_value(line, "duration_ms")) : result.duration_ms;
                result.events.push_back(JsonEvent{"result", result.final_text, "", {}, {}});
            } else if (sub == "error") {
                result.error = extract_string(line, "error");
                result.events.push_back(JsonEvent{"error", result.error, "", {}, {}});
            }
        }
    }
    return result;
}

ParsedJsonOutput parse_kimi_json(const std::string& raw_stdout) {
    ParsedJsonOutput result;
    result.schema_name = "kimi";
    auto lines = split_lines(raw_stdout);

    static const std::vector<std::string> passthrough = {
        "TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd", "StatusUpdate",
        "HookTriggered", "HookResolved", "ApprovalRequest", "SubagentEvent", "ToolCallRequest"
    };

    for (const auto& line : lines) {
        if (line.empty() || line[0] != '{') continue;

        std::string wire_type = extract_string(line, "type");
        if (!wire_type.empty()) {
            for (const auto& pt : passthrough) {
                if (wire_type == pt) {
                    result.events.push_back(JsonEvent{to_lower(wire_type), "", "", {}, {}});
                    goto next_line;
                }
            }
        }

        {
            std::string role = extract_string(line, "role");

            if (role == "assistant") {
                std::string content_raw = extract_raw_value(line, "content");
                auto tool_calls_arr = extract_subobject(line, "tool_calls");

                if (content_raw.size() >= 2 && content_raw[0] == '"') {
                    std::string text = extract_string(line, "content");
                    result.final_text = text;
                    result.events.push_back(JsonEvent{"assistant", text, "", {}, {}});
                } else if (content_raw.size() >= 1 && content_raw[0] == '[') {
                    auto blocks = extract_content_blocks(line, "content");
                    std::vector<std::string> texts;
                    for (auto& b : blocks) {
                        if (b.type == "text") texts.push_back(b.text);
                        else if (b.type == "think")
                            result.events.push_back(JsonEvent{"thinking", "", b.think, {}, {}});
                    }
                    if (!texts.empty()) {
                        std::string text;
                        for (size_t i = 0; i < texts.size(); i++) {
                            if (i > 0) text += "\n";
                            text += texts[i];
                        }
                        result.final_text = text;
                        result.events.push_back(JsonEvent{"assistant", text, "", {}, {}});
                    }
                }

                if (!tool_calls_arr.empty() && tool_calls_arr[0] == '[') {
                    size_t pos = 1;
                    while (pos < tool_calls_arr.size()) {
                        while (pos < tool_calls_arr.size() && (tool_calls_arr[pos] == ' ' || tool_calls_arr[pos] == '\t' || tool_calls_arr[pos] == ',' || tool_calls_arr[pos] == '\n')) pos++;
                        if (pos >= tool_calls_arr.size() || tool_calls_arr[pos] == ']') break;
                        if (tool_calls_arr[pos] == '{') {
                            int depth = 0;
                            size_t start = pos;
                            while (pos < tool_calls_arr.size()) {
                                if (tool_calls_arr[pos] == '{') depth++;
                                else if (tool_calls_arr[pos] == '}') { depth--; if (depth == 0) break; }
                                pos++;
                            }
                            std::string tc_obj = tool_calls_arr.substr(start, pos - start + 1);
                            std::string fn = extract_subobject(tc_obj, "function");
                            ToolCall tc{extract_string(tc_obj, "id"), extract_string(fn, "name"), extract_string(fn, "arguments")};
                            result.events.push_back(JsonEvent{"tool_call", "", "", tc, {}});
                            pos++;
                        } else pos++;
                    }
                }
            } else if (role == "tool") {
                auto blocks = extract_content_blocks(line, "content");
                std::vector<std::string> texts;
                for (auto& b : blocks) {
                    if (b.type == "text") {
                        if (b.text.size() >= 8 && b.text.substr(0, 8) == "<system>") continue;
                        texts.push_back(b.text);
                    }
                }
                std::string content;
                for (size_t i = 0; i < texts.size(); i++) {
                    if (i > 0) content += "\n";
                    content += texts[i];
                }
                ToolResult tr{extract_string(line, "tool_call_id"), content, false};
                result.events.push_back(JsonEvent{"tool_result", "", "", {}, tr});
            }
        }
        next_line:;
    }
    return result;
}

ParsedJsonOutput parse_json_output(const std::string& raw_stdout, const std::string& schema) {
    if (schema == "opencode") return parse_opencode_json(raw_stdout);
    if (schema == "claude-code") return parse_claude_code_json(raw_stdout);
    if (schema == "kimi") return parse_kimi_json(raw_stdout);
    ParsedJsonOutput result;
    result.schema_name = schema;
    result.error = "unknown schema: " + schema;
    return result;
}

std::string render_parsed(const ParsedJsonOutput& output) {
    std::vector<std::string> parts;
    for (const auto& event : output.events) {
        if (event.event_type == "text" || event.event_type == "assistant" || event.event_type == "result") {
            if (!event.text.empty()) parts.push_back(event.text);
        } else if (event.event_type == "thinking_delta" || event.event_type == "thinking") {
            if (!event.thinking.empty()) parts.push_back("[thinking] " + event.thinking);
        } else if (event.event_type == "tool_use") {
            if (event.tool_call.has_value()) parts.push_back("[tool] " + event.tool_call->name);
        } else if (event.event_type == "tool_result") {
            if (event.tool_result.has_value()) parts.push_back("[tool_result] " + event.tool_result->content);
        } else if (event.event_type == "error") {
            if (!event.text.empty()) parts.push_back("[error] " + event.text);
        }
    }
    if (!parts.empty()) {
        std::string result;
        for (size_t i = 0; i < parts.size(); i++) {
            if (i > 0) result += "\n";
            result += parts[i];
        }
        return result;
    }
    return output.final_text;
}

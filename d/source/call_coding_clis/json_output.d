module call_coding_clis.json_output;

import std.json;
import std.string : strip, join, splitLines, toLower;
import std.conv : to;
import std.array : appender;
import std.algorithm : startsWith;

struct ToolCall {
    string id;
    string name;
    string arguments;
}

struct ToolResult {
    string toolCallId;
    string content;
    bool isError;
}

struct JsonEvent {
    string eventType;
    string text;
    string thinking;
    ToolCall* toolCall;
    ToolResult* toolResult;
}

struct ParsedJsonOutput {
    string schemaName;
    JsonEvent[] events;
    string finalText;
    string sessionId;
    string errorText;
    double costUsd;
    long durationMs;
}

private string getStr(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.string) return (*p).str;
    }
    return "";
}

private bool getBool(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.true_ || (*p).type == JSONType.false_)
            return (*p).boolean;
    }
    return false;
}

private double getFloat(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.float_) return (*p).floating;
        if ((*p).type == JSONType.integer) return cast(double)(*p).integer;
    }
    return 0.0;
}

private long getLong(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.integer) return (*p).integer;
        if ((*p).type == JSONType.float_) return cast(long)(*p).floating;
    }
    return 0;
}

private JSONValue getObj(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.object) return *p;
    }
    return JSONValue();
}

private JSONValue[] getArr(JSONValue obj, string key) {
    if (auto p = key in obj.object) {
        if ((*p).type == JSONType.array) return (*p).array;
    }
    return null;
}

ParsedJsonOutput parseOpencodeJson(string rawStdout) {
    ParsedJsonOutput result;
    result.schemaName = "opencode";

    foreach (rawLine; rawStdout.strip.splitLines()) {
        auto line = rawLine.strip;
        if (line.length == 0) continue;
        JSONValue obj;
        try { obj = parseJSON(line); } catch (JSONException) continue;

        if ("response" in obj.object) {
            auto text = getStr(obj, "response");
            result.finalText = text;
            JsonEvent ev;
            ev.eventType = "text";
            ev.text = text;
            result.events ~= ev;
        } else if ("error" in obj.object) {
            auto err = getStr(obj, "error");
            result.errorText = err;
            JsonEvent ev;
            ev.eventType = "error";
            ev.text = err;
            result.events ~= ev;
        }
    }
    return result;
}

ParsedJsonOutput parseClaudeCodeJson(string rawStdout) {
    ParsedJsonOutput result;
    result.schemaName = "claude-code";

    foreach (rawLine; rawStdout.strip.splitLines()) {
        auto line = rawLine.strip;
        if (line.length == 0) continue;
        JSONValue obj;
        try { obj = parseJSON(line); } catch (JSONException) continue;

        auto msgType = getStr(obj, "type");

        if (msgType == "system") {
            auto sub = getStr(obj, "subtype");
            if (sub == "init") {
                result.sessionId = getStr(obj, "session_id");
            } else if (sub == "api_retry") {
                JsonEvent ev; ev.eventType = "system_retry";
                result.events ~= ev;
            }

        } else if (msgType == "assistant") {
            auto message = getObj(obj, "message");
            auto content = getArr(message, "content");
            string[] texts;
            foreach (block; content) {
                if (block.type == JSONType.object && getStr(block, "type") == "text") {
                    texts ~= getStr(block, "text");
                }
            }
            if (texts.length > 0) {
                auto text = texts.join("\n");
                result.finalText = text;
                JsonEvent ev; ev.eventType = "assistant"; ev.text = text;
                result.events ~= ev;
            }

        } else if (msgType == "stream_event") {
            auto event = getObj(obj, "event");
            auto evType = getStr(event, "type");
            if (evType == "content_block_delta") {
                auto delta = getObj(event, "delta");
                auto dType = getStr(delta, "type");
                if (dType == "text_delta") {
                    JsonEvent ev; ev.eventType = "text_delta"; ev.text = getStr(delta, "text");
                    result.events ~= ev;
                } else if (dType == "thinking_delta") {
                    JsonEvent ev; ev.eventType = "thinking_delta"; ev.thinking = getStr(delta, "thinking");
                    result.events ~= ev;
                } else if (dType == "input_json_delta") {
                    JsonEvent ev; ev.eventType = "tool_input_delta"; ev.text = getStr(delta, "partial_json");
                    result.events ~= ev;
                }
            } else if (evType == "content_block_start") {
                auto cb = getObj(event, "content_block");
                auto cbType = getStr(cb, "type");
                if (cbType == "thinking") {
                    JsonEvent ev; ev.eventType = "thinking_start";
                    result.events ~= ev;
                } else if (cbType == "tool_use") {
                    auto tc = new ToolCall;
                    tc.id = getStr(cb, "id");
                    tc.name = getStr(cb, "name");
                    tc.arguments = "";
                    JsonEvent ev; ev.eventType = "tool_use_start"; ev.toolCall = tc;
                    result.events ~= ev;
                }
            }

        } else if (msgType == "tool_use") {
            auto tc = new ToolCall;
            tc.name = getStr(obj, "tool_name");
            auto ti = "tool_input" in obj.object;
            tc.arguments = ti !is null ? (*ti).toString() : "{}";
            JsonEvent ev; ev.eventType = "tool_use"; ev.toolCall = tc;
            result.events ~= ev;

        } else if (msgType == "tool_result") {
            auto tr = new ToolResult;
            tr.toolCallId = getStr(obj, "tool_use_id");
            tr.content = getStr(obj, "content");
            tr.isError = getBool(obj, "is_error");
            JsonEvent ev; ev.eventType = "tool_result"; ev.toolResult = tr;
            result.events ~= ev;

        } else if (msgType == "result") {
            auto sub = getStr(obj, "subtype");
            if (sub == "success") {
                auto res = getStr(obj, "result");
                if (res.length > 0) result.finalText = res;
                result.costUsd = getFloat(obj, "cost_usd");
                result.durationMs = getLong(obj, "duration_ms");
                JsonEvent ev; ev.eventType = "result"; ev.text = result.finalText;
                result.events ~= ev;
            } else if (sub == "error") {
                auto err = getStr(obj, "error");
                result.errorText = err;
                JsonEvent ev; ev.eventType = "error"; ev.text = err;
                result.events ~= ev;
            }
        }
    }
    return result;
}

private bool isKimiPassthrough(string wireType) {
    foreach (pt; ["TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd",
        "StatusUpdate", "HookTriggered", "HookResolved", "ApprovalRequest",
        "SubagentEvent", "ToolCallRequest"]) {
        if (wireType == pt) return true;
    }
    return false;
}

ParsedJsonOutput parseKimiJson(string rawStdout) {
    ParsedJsonOutput result;
    result.schemaName = "kimi";

    foreach (rawLine; rawStdout.strip.splitLines()) {
        auto line = rawLine.strip;
        if (line.length == 0) continue;
        JSONValue obj;
        try { obj = parseJSON(line); } catch (JSONException) continue;

        auto wireType = getStr(obj, "type");
        if (wireType.length > 0 && isKimiPassthrough(wireType)) {
            JsonEvent ev; ev.eventType = wireType.toLower();
            result.events ~= ev;
            continue;
        }

        auto role = getStr(obj, "role");
        if (role == "assistant") {
            auto contentVal = "content" in obj.object;
            if (contentVal !is null) {
                auto cv = *contentVal;
                if (cv.type == JSONType.string) {
                    result.finalText = cv.str;
                    JsonEvent ev; ev.eventType = "assistant"; ev.text = cv.str;
                    result.events ~= ev;
                } else if (cv.type == JSONType.array) {
                    string[] texts;
                    foreach (part; cv.array) {
                        if (part.type == JSONType.object) {
                            auto pt = getStr(part, "type");
                            if (pt == "text") {
                                texts ~= getStr(part, "text");
                            } else if (pt == "think") {
                                JsonEvent ev; ev.eventType = "thinking";
                                ev.thinking = getStr(part, "think");
                                result.events ~= ev;
                            }
                        }
                    }
                    if (texts.length > 0) {
                        auto text = texts.join("\n");
                        result.finalText = text;
                        JsonEvent ev; ev.eventType = "assistant"; ev.text = text;
                        result.events ~= ev;
                    }
                }
            }

            auto toolCalls = getArr(obj, "tool_calls");
            foreach (tcData; toolCalls) {
                if (tcData.type == JSONType.object) {
                    auto tc = new ToolCall;
                    tc.id = getStr(tcData, "id");
                    auto fn = getObj(tcData, "function");
                    tc.name = getStr(fn, "name");
                    tc.arguments = getStr(fn, "arguments");
                    JsonEvent ev; ev.eventType = "tool_call"; ev.toolCall = tc;
                    result.events ~= ev;
                }
            }

        } else if (role == "tool") {
            auto content = getArr(obj, "content");
            string[] texts;
            foreach (part; content) {
                if (part.type == JSONType.object && getStr(part, "type") == "text") {
                    auto t = getStr(part, "text");
                    if (!t.startsWith("<system>")) texts ~= t;
                }
            }
            auto tr = new ToolResult;
            tr.toolCallId = getStr(obj, "tool_call_id");
            tr.content = texts.join("\n");
            JsonEvent ev; ev.eventType = "tool_result"; ev.toolResult = tr;
            result.events ~= ev;
        }
    }
    return result;
}

ParsedJsonOutput parseJsonOutput(string rawStdout, string schema) {
    if (schema == "opencode") return parseOpencodeJson(rawStdout);
    if (schema == "claude-code") return parseClaudeCodeJson(rawStdout);
    if (schema == "kimi") return parseKimiJson(rawStdout);
    ParsedJsonOutput result;
    result.schemaName = schema;
    result.errorText = "unknown schema: " ~ schema;
    return result;
}

string renderParsed(ref ParsedJsonOutput output) {
    string[] parts;
    foreach (ev; output.events) {
        if (ev.eventType == "text" || ev.eventType == "assistant" || ev.eventType == "result") {
            if (ev.text.length > 0) parts ~= ev.text;
        } else if (ev.eventType == "thinking_delta" || ev.eventType == "thinking") {
            if (ev.thinking.length > 0) parts ~= "[thinking] " ~ ev.thinking;
        } else if (ev.eventType == "tool_use") {
            if (ev.toolCall !is null) parts ~= "[tool] " ~ ev.toolCall.name;
        } else if (ev.eventType == "tool_result") {
            if (ev.toolResult !is null) parts ~= "[tool_result] " ~ ev.toolResult.content;
        } else if (ev.eventType == "error") {
            if (ev.text.length > 0) parts ~= "[error] " ~ ev.text;
        }
    }
    return parts.length > 0 ? parts.join("\n") : output.finalText;
}

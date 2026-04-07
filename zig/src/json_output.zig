const std = @import("std");

pub const ToolCall = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    arguments: []const u8 = "",
};

pub const ToolResult = struct {
    tool_call_id: []const u8 = "",
    content: []const u8 = "",
    is_error: bool = false,
};

pub const JsonEvent = struct {
    event_type: []const u8,
    text: []const u8 = "",
    thinking: []const u8 = "",
    tool_call: ?ToolCall = null,
    tool_result: ?ToolResult = null,
};

pub const ParsedJsonOutput = struct {
    allocator: std.mem.Allocator,
    schema_name: []const u8,
    events: std.ArrayList(JsonEvent),
    final_text: []const u8 = "",
    session_id: []const u8 = "",
    error_text: []const u8 = "",
    cost_usd: f64 = 0.0,
    duration_ms: i64 = 0,
    owned: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, schema: []const u8) ParsedJsonOutput {
        return .{
            .allocator = allocator,
            .schema_name = schema,
            .events = .empty,
            .owned = .empty,
        };
    }

    fn dupe(self: *ParsedJsonOutput, s: []const u8) ![]const u8 {
        if (s.len == 0) return "";
        const copy = try self.allocator.dupe(u8, s);
        try self.owned.append(self.allocator, copy);
        return copy;
    }

    pub fn deinit(self: *ParsedJsonOutput) void {
        for (self.owned.items) |s| {
            if (s.len > 0) self.allocator.free(s);
        }
        self.owned.deinit(self.allocator);
        self.events.deinit(self.allocator);
    }
};

fn strVal(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v == .string) return v.string;
    return null;
}

fn boolVal(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    if (v == .bool) return v.bool;
    return null;
}

fn floatVal(obj: std.json.ObjectMap, key: []const u8) ?f64 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .float => |f| f,
        .integer => |i| @as(f64, @floatFromInt(i)),
        else => null,
    };
}

fn intVal(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .integer => |i| i,
        else => null,
    };
}

fn asObj(v: std.json.Value) ?std.json.ObjectMap {
    if (v == .object) return v.object;
    return null;
}

fn objAt(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const v = obj.get(key) orelse return null;
    return asObj(v);
}

fn arrAt(obj: std.json.ObjectMap, key: []const u8) ?[]const std.json.Value {
    const v = obj.get(key) orelse return null;
    if (v == .array) return v.array.items;
    return null;
}

pub fn parseOpencodeJson(allocator: std.mem.Allocator, raw_stdout: []const u8) !ParsedJsonOutput {
    var result = ParsedJsonOutput.init(allocator, "opencode");
    errdefer result.deinit();

    const trimmed_input = std.mem.trim(u8, raw_stdout, " \t\n\r");
    if (trimmed_input.len == 0) return result;

    var iter = std.mem.splitScalar(u8, trimmed_input, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        const map = root.object;

        if (map.get("response")) |val| {
            const text = if (val == .string) val.string else "";
            const duped = try result.dupe(text);
            result.final_text = duped;
            try result.events.append(allocator, .{
                .event_type = "text",
                .text = duped,
            });
        } else if (map.get("error")) |val| {
            const err_str = if (val == .string) val.string else "";
            const duped = try result.dupe(err_str);
            result.error_text = duped;
            try result.events.append(allocator, .{
                .event_type = "error",
                .text = duped,
            });
        }
    }
    return result;
}

pub fn parseClaudeCodeJson(allocator: std.mem.Allocator, raw_stdout: []const u8) !ParsedJsonOutput {
    var result = ParsedJsonOutput.init(allocator, "claude-code");
    errdefer result.deinit();

    const trimmed_input = std.mem.trim(u8, raw_stdout, " \t\n\r");
    if (trimmed_input.len == 0) return result;

    var iter = std.mem.splitScalar(u8, trimmed_input, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        const map = root.object;

        const msg_type = strVal(map, "type") orelse "";

        if (std.mem.eql(u8, msg_type, "system")) {
            const sub = strVal(map, "subtype") orelse "";
            if (std.mem.eql(u8, sub, "init")) {
                result.session_id = try result.dupe(strVal(map, "session_id") orelse "");
            } else if (std.mem.eql(u8, sub, "api_retry")) {
                try result.events.append(allocator, .{ .event_type = "system_retry" });
            }
        } else if (std.mem.eql(u8, msg_type, "assistant")) {
            const message = objAt(map, "message");
            if (message) |msg| {
                const content = arrAt(msg, "content") orelse &.{};
                var texts = std.ArrayList([]const u8).empty;
                defer texts.deinit(allocator);
                for (content) |block| {
                    if (asObj(block)) |b| {
                        if (strVal(b, "type")) |bt| {
                            if (std.mem.eql(u8, bt, "text")) {
                                try texts.append(allocator, strVal(b, "text") orelse "");
                            }
                        }
                    }
                }
                if (texts.items.len > 0) {
                    const joined = try std.mem.join(allocator, "\n", texts.items);
                    const duped = try result.dupe(joined);
                    allocator.free(joined);
                    result.final_text = duped;
                    try result.events.append(allocator, .{
                        .event_type = "assistant",
                        .text = duped,
                    });
                }
            }
        } else if (std.mem.eql(u8, msg_type, "stream_event")) {
            const event = objAt(map, "event");
            if (event) |ev| {
                const ev_type = strVal(ev, "type") orelse "";
                if (std.mem.eql(u8, ev_type, "content_block_delta")) {
                    const delta = objAt(ev, "delta");
                    if (delta) |d| {
                        const d_type = strVal(d, "type") orelse "";
                        if (std.mem.eql(u8, d_type, "text_delta")) {
                            try result.events.append(allocator, .{
                                .event_type = "text_delta",
                                .text = try result.dupe(strVal(d, "text") orelse ""),
                            });
                        } else if (std.mem.eql(u8, d_type, "thinking_delta")) {
                            try result.events.append(allocator, .{
                                .event_type = "thinking_delta",
                                .thinking = try result.dupe(strVal(d, "thinking") orelse ""),
                            });
                        } else if (std.mem.eql(u8, d_type, "input_json_delta")) {
                            try result.events.append(allocator, .{
                                .event_type = "tool_input_delta",
                                .text = try result.dupe(strVal(d, "partial_json") orelse ""),
                            });
                        }
                    }
                } else if (std.mem.eql(u8, ev_type, "content_block_start")) {
                    const cb = objAt(ev, "content_block");
                    if (cb) |c| {
                        const cb_type = strVal(c, "type") orelse "";
                        if (std.mem.eql(u8, cb_type, "thinking")) {
                            try result.events.append(allocator, .{ .event_type = "thinking_start" });
                        } else if (std.mem.eql(u8, cb_type, "tool_use")) {
                            try result.events.append(allocator, .{
                                .event_type = "tool_use_start",
                                .tool_call = .{
                                    .id = try result.dupe(strVal(c, "id") orelse ""),
                                    .name = try result.dupe(strVal(c, "name") orelse ""),
                                    .arguments = "",
                                },
                            });
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, msg_type, "tool_use")) {
            const args = blk: {
                break :blk "";
            };
            try result.events.append(allocator, .{
                .event_type = "tool_use",
                .tool_call = .{
                    .name = try result.dupe(strVal(map, "tool_name") orelse ""),
                    .arguments = args,
                },
            });
        } else if (std.mem.eql(u8, msg_type, "tool_result")) {
            try result.events.append(allocator, .{
                .event_type = "tool_result",
                .tool_result = .{
                    .tool_call_id = try result.dupe(strVal(map, "tool_use_id") orelse ""),
                    .content = try result.dupe(strVal(map, "content") orelse ""),
                    .is_error = boolVal(map, "is_error") orelse false,
                },
            });
        } else if (std.mem.eql(u8, msg_type, "result")) {
            const sub = strVal(map, "subtype") orelse "";
            if (std.mem.eql(u8, sub, "success")) {
                const res_text = strVal(map, "result") orelse "";
                if (res_text.len > 0) {
                    result.final_text = try result.dupe(res_text);
                }
                result.cost_usd = floatVal(map, "cost_usd") orelse 0.0;
                result.duration_ms = intVal(map, "duration_ms") orelse 0;
                try result.events.append(allocator, .{
                    .event_type = "result",
                    .text = result.final_text,
                });
            } else if (std.mem.eql(u8, sub, "error")) {
                const err_str = strVal(map, "error") orelse "";
                result.error_text = try result.dupe(err_str);
                try result.events.append(allocator, .{
                    .event_type = "error",
                    .text = result.error_text,
                });
            }
        }
    }
    return result;
}

const kimi_passthrough = [_][]const u8{
    "TurnBegin",       "StepBegin",       "StepInterrupted",
    "TurnEnd",         "StatusUpdate",    "HookTriggered",
    "HookResolved",    "ApprovalRequest", "SubagentEvent",
    "ToolCallRequest",
};

pub fn parseKimiJson(allocator: std.mem.Allocator, raw_stdout: []const u8) !ParsedJsonOutput {
    var result = ParsedJsonOutput.init(allocator, "kimi");
    errdefer result.deinit();

    const trimmed_input = std.mem.trim(u8, raw_stdout, " \t\n\r");
    if (trimmed_input.len == 0) return result;

    var iter = std.mem.splitScalar(u8, trimmed_input, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        const map = root.object;

        const wire_type = strVal(map, "type") orelse "";
        var passthrough_hit = false;
        if (wire_type.len > 0) {
            for (kimi_passthrough) |pt| {
                if (std.mem.eql(u8, wire_type, pt)) {
                    var lower_buf: [64]u8 = undefined;
                    const lower = std.ascii.lowerString(&lower_buf, wire_type);
                    try result.events.append(allocator, .{
                        .event_type = try result.dupe(lower),
                    });
                    passthrough_hit = true;
                    break;
                }
            }
        }
        if (passthrough_hit) continue;

        const role = strVal(map, "role") orelse "";
        if (std.mem.eql(u8, role, "assistant")) {
            try parseKimiAssistant(allocator, &result, map);
        } else if (std.mem.eql(u8, role, "tool")) {
            try parseKimiTool(allocator, &result, map);
        }
    }
    return result;
}

fn parseKimiAssistant(allocator: std.mem.Allocator, result: *ParsedJsonOutput, map: std.json.ObjectMap) !void {
    const content_val = map.get("content");
    const tool_calls = arrAt(map, "tool_calls");

    if (content_val) |cv| {
        if (cv == .string) {
            result.final_text = try result.dupe(cv.string);
            try result.events.append(allocator, .{
                .event_type = "assistant",
                .text = result.final_text,
            });
        } else if (cv == .array) {
            var texts = std.ArrayList([]const u8).empty;
            defer texts.deinit(allocator);
            for (cv.array.items) |part| {
                if (asObj(part)) |p| {
                    const pt = strVal(p, "type") orelse "";
                    if (std.mem.eql(u8, pt, "text")) {
                        try texts.append(allocator, strVal(p, "text") orelse "");
                    } else if (std.mem.eql(u8, pt, "think")) {
                        try result.events.append(allocator, .{
                            .event_type = "thinking",
                            .thinking = try result.dupe(strVal(p, "think") orelse ""),
                        });
                    }
                }
            }
            if (texts.items.len > 0) {
                const joined = try std.mem.join(allocator, "\n", texts.items);
                result.final_text = try result.dupe(joined);
                allocator.free(joined);
                try result.events.append(allocator, .{
                    .event_type = "assistant",
                    .text = result.final_text,
                });
            }
        }
    }

    if (tool_calls) |tcs| {
        for (tcs) |tc_data| {
            if (asObj(tc_data)) |tc| {
                const fn_obj = objAt(tc, "function");
                const fn_name = if (fn_obj) |f| strVal(f, "name") orelse "" else "";
                const fn_args = if (fn_obj) |f| strVal(f, "arguments") orelse "" else "";
                try result.events.append(allocator, .{
                    .event_type = "tool_call",
                    .tool_call = .{
                        .id = try result.dupe(strVal(tc, "id") orelse ""),
                        .name = try result.dupe(fn_name),
                        .arguments = try result.dupe(fn_args),
                    },
                });
            }
        }
    }
}

fn parseKimiTool(allocator: std.mem.Allocator, result: *ParsedJsonOutput, map: std.json.ObjectMap) !void {
    const content = arrAt(map, "content") orelse &.{};
    var texts = std.ArrayList([]const u8).empty;
    defer texts.deinit(allocator);
    for (content) |part| {
        if (asObj(part)) |p| {
            const pt = strVal(p, "type") orelse "";
            if (std.mem.eql(u8, pt, "text")) {
                const t = strVal(p, "text") orelse "";
                if (!std.mem.startsWith(u8, t, "<system>")) {
                    try texts.append(allocator, t);
                }
            }
        }
    }
    const joined = try std.mem.join(allocator, "\n", texts.items);
    const content_str = try result.dupe(joined);
    allocator.free(joined);
    try result.events.append(allocator, .{
        .event_type = "tool_result",
        .tool_result = .{
            .tool_call_id = try result.dupe(strVal(map, "tool_call_id") orelse ""),
            .content = content_str,
        },
    });
}

pub fn parseJsonOutput(allocator: std.mem.Allocator, raw_stdout: []const u8, schema: []const u8) !ParsedJsonOutput {
    if (std.mem.eql(u8, schema, "opencode")) {
        return parseOpencodeJson(allocator, raw_stdout);
    } else if (std.mem.eql(u8, schema, "claude-code")) {
        return parseClaudeCodeJson(allocator, raw_stdout);
    } else if (std.mem.eql(u8, schema, "kimi")) {
        return parseKimiJson(allocator, raw_stdout);
    } else {
        var result = ParsedJsonOutput.init(allocator, schema);
        const msg = try std.fmt.allocPrint(allocator, "unknown schema: {s}", .{schema});
        try result.owned.append(result.allocator, msg);
        result.error_text = msg;
        return result;
    }
}

pub fn renderParsed(allocator: std.mem.Allocator, output: *const ParsedJsonOutput) ![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var to_free = std.ArrayList([]const u8).empty;
    defer {
        for (to_free.items) |s| allocator.free(s);
        to_free.deinit(allocator);
    }

    for (output.events.items) |event| {
        const et = event.event_type;
        if (std.mem.eql(u8, et, "text") or std.mem.eql(u8, et, "assistant") or std.mem.eql(u8, et, "result")) {
            if (event.text.len > 0) try parts.append(allocator, event.text);
        } else if (std.mem.eql(u8, et, "thinking_delta") or std.mem.eql(u8, et, "thinking")) {
            if (event.thinking.len > 0) {
                const f = try std.fmt.allocPrint(allocator, "[thinking] {s}", .{event.thinking});
                try to_free.append(allocator, f);
                try parts.append(allocator, f);
            }
        } else if (std.mem.eql(u8, et, "tool_use")) {
            if (event.tool_call) |tc| {
                const f = try std.fmt.allocPrint(allocator, "[tool] {s}", .{tc.name});
                try to_free.append(allocator, f);
                try parts.append(allocator, f);
            }
        } else if (std.mem.eql(u8, et, "tool_result")) {
            if (event.tool_result) |tr| {
                const f = try std.fmt.allocPrint(allocator, "[tool_result] {s}", .{tr.content});
                try to_free.append(allocator, f);
                try parts.append(allocator, f);
            }
        } else if (std.mem.eql(u8, et, "error")) {
            if (event.text.len > 0) {
                const f = try std.fmt.allocPrint(allocator, "[error] {s}", .{event.text});
                try to_free.append(allocator, f);
                try parts.append(allocator, f);
            }
        }
    }

    if (parts.items.len > 0) {
        return try std.mem.join(allocator, "\n", parts.items);
    }
    return try allocator.dupe(u8, output.final_text);
}

test "parse opencode response" {
    const allocator = std.testing.allocator;
    const input = "{\"response\": \"hello world\"}\n";
    var result = try parseOpencodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("text", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("hello world", result.events.items[0].text);
    try std.testing.expectEqualStrings("hello world", result.final_text);
}

test "parse opencode error" {
    const allocator = std.testing.allocator;
    const input = "{\"error\": \"something broke\"}\n";
    var result = try parseOpencodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("error", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("something broke", result.error_text);
}

test "parse opencode skips invalid json" {
    const allocator = std.testing.allocator;
    const input = "not json\n{\"response\": \"ok\"}\n";
    var result = try parseOpencodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("ok", result.final_text);
}

test "parse claude system init" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-123\"}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expectEqualStrings("sess-123", result.session_id);
}

test "parse claude assistant" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("assistant", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("hello", result.final_text);
}

test "parse claude text delta" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("text_delta", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("hi", result.events.items[0].text);
}

test "parse claude tool use" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"tool_use\",\"tool_name\":\"read_file\",\"tool_input\":{\"path\":\"/tmp/x\"}}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("tool_use", result.events.items[0].event_type);
    const tc = result.events.items[0].tool_call orelse unreachable;
    try std.testing.expectEqualStrings("read_file", tc.name);
}

test "parse claude tool result" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"tool_result\",\"tool_use_id\":\"tu-1\",\"content\":\"file contents\",\"is_error\":false}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    const tr = result.events.items[0].tool_result orelse unreachable;
    try std.testing.expectEqualStrings("tu-1", tr.tool_call_id);
    try std.testing.expectEqualStrings("file contents", tr.content);
    try std.testing.expect(!tr.is_error);
}

test "parse claude result success" {
    const allocator = std.testing.allocator;
    const input = "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"done\",\"cost_usd\":0.05,\"duration_ms\":1200}\n";
    var result = try parseClaudeCodeJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("result", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("done", result.final_text);
    try std.testing.expectEqual(@as(f64, 0.05), result.cost_usd);
    try std.testing.expectEqual(@as(i64, 1200), result.duration_ms);
}

test "parse kimi assistant text" {
    const allocator = std.testing.allocator;
    const input = "{\"role\":\"assistant\",\"content\":\"hello kimi\"}\n";
    var result = try parseKimiJson(allocator, input);
    defer result.deinit();
    try std.testing.expect(result.events.items.len == 1);
    try std.testing.expectEqualStrings("assistant", result.events.items[0].event_type);
    try std.testing.expectEqualStrings("hello kimi", result.final_text);
}

test "parse kimi tool calls" {
    const allocator = std.testing.allocator;
    const input = "{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"tc-1\",\"function\":{\"name\":\"bash\",\"arguments\":\"{\\\"cmd\\\":\\\"ls\\\"}\"}}]}\n";
    var result = try parseKimiJson(allocator, input);
    defer result.deinit();
    var found = false;
    for (result.events.items) |ev| {
        if (std.mem.eql(u8, ev.event_type, "tool_call")) {
            if (ev.tool_call) |tc| {
                if (std.mem.eql(u8, tc.name, "bash")) found = true;
            }
        }
    }
    try std.testing.expect(found);
}

test "parse json output dispatches" {
    const allocator = std.testing.allocator;
    var r1 = try parseJsonOutput(allocator, "{\"response\": \"ok\"}\n", "opencode");
    defer r1.deinit();
    try std.testing.expectEqualStrings("opencode", r1.schema_name);
    try std.testing.expectEqualStrings("ok", r1.final_text);
}

test "parse json output unknown schema" {
    const allocator = std.testing.allocator;
    var r1 = try parseJsonOutput(allocator, "", "unknown");
    defer r1.deinit();
    try std.testing.expect(r1.error_text.len > 0);
}

test "render parsed text" {
    const allocator = std.testing.allocator;
    var r = ParsedJsonOutput.init(allocator, "test");
    defer r.deinit();
    try r.events.append(allocator, .{ .event_type = "text", .text = try r.dupe("hello") });
    try r.events.append(allocator, .{ .event_type = "assistant", .text = try r.dupe("world") });
    const rendered = try renderParsed(allocator, &r);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("hello\nworld", rendered);
}

test "render parsed thinking" {
    const allocator = std.testing.allocator;
    var r = ParsedJsonOutput.init(allocator, "test");
    defer r.deinit();
    try r.events.append(allocator, .{ .event_type = "thinking", .thinking = try r.dupe("hmm") });
    const rendered = try renderParsed(allocator, &r);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("[thinking] hmm", rendered);
}

test "render parsed tool use and result" {
    const allocator = std.testing.allocator;
    var r = ParsedJsonOutput.init(allocator, "test");
    defer r.deinit();
    try r.events.append(allocator, .{
        .event_type = "tool_use",
        .tool_call = .{ .name = try r.dupe("read") },
    });
    try r.events.append(allocator, .{
        .event_type = "tool_result",
        .tool_result = .{ .content = try r.dupe("output") },
    });
    const rendered = try renderParsed(allocator, &r);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("[tool] read\n[tool_result] output", rendered);
}

test "render parsed fallback to final_text" {
    const allocator = std.testing.allocator;
    var r = ParsedJsonOutput.init(allocator, "test");
    r.final_text = try r.dupe("fallback");
    defer r.deinit();
    const rendered = try renderParsed(allocator, &r);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("fallback", rendered);
}

test "render parsed error" {
    const allocator = std.testing.allocator;
    var r = ParsedJsonOutput.init(allocator, "test");
    defer r.deinit();
    try r.events.append(allocator, .{ .event_type = "error", .text = try r.dupe("oops") });
    const rendered = try renderParsed(allocator, &r);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("[error] oops", rendered);
}

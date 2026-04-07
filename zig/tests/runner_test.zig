const std = @import("std");
const runner = @import("runner");
const prompt_spec = @import("prompt_spec");

var stream_events: std.ArrayList(struct { []const u8, []const u8 }) = undefined;
var stream_alloc: std.mem.Allocator = undefined;

fn onStreamEvent(event_type: []const u8, data: []const u8) void {
    stream_events.append(stream_alloc, .{ event_type, data }) catch {};
}

test "buildPromptSpec valid prompt" {
    const allocator = std.testing.allocator;
    const spec = try prompt_spec.buildPromptSpec(allocator, "hello");
    defer prompt_spec.freePromptSpec(allocator, spec);

    try std.testing.expectEqualStrings("opencode", spec.argv[0]);
    try std.testing.expectEqualStrings("run", spec.argv[1]);
    try std.testing.expectEqualStrings("hello", spec.argv[2]);
}

test "buildPromptSpec empty prompt" {
    const allocator = std.testing.allocator;
    const result = prompt_spec.buildPromptSpec(allocator, "");
    try std.testing.expectError(error.EmptyPrompt, result);
}

test "buildPromptSpec whitespace-only prompt" {
    const allocator = std.testing.allocator;
    const result = prompt_spec.buildPromptSpec(allocator, "   ");
    try std.testing.expectError(error.EmptyPrompt, result);
}

test "buildPromptSpec trims whitespace" {
    const allocator = std.testing.allocator;
    const spec = try prompt_spec.buildPromptSpec(allocator, "  foo  ");
    defer prompt_spec.freePromptSpec(allocator, spec);

    try std.testing.expectEqualStrings("foo", spec.argv[2]);
}

test "Runner run echo" {
    const allocator = std.testing.allocator;

    const spec = runner.CommandSpec{
        .argv = &.{ "echo", "hello" },
    };

    const result = try runner.Runner.run(allocator, spec);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout_data, "hello") != null);
    try std.testing.expectEqualStrings("", result.stderr_data);
}

test "Runner run nonexistent binary" {
    const allocator = std.testing.allocator;

    const spec = runner.CommandSpec{
        .argv = &.{"/nonexistent_binary_xyz"},
    };

    const result = try runner.Runner.run(allocator, spec);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.startsWith(u8, result.stderr_data, "failed to start /nonexistent_binary_xyz:"));
    try std.testing.expectEqualStrings("", result.stdout_data);
}

test "Runner run exit code forwarding" {
    const allocator = std.testing.allocator;

    const spec = runner.CommandSpec{
        .argv = &.{ "sh", "-c", "exit 42" },
    };

    const result = try runner.Runner.run(allocator, spec);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 42), result.exit_code);
}

test "Runner stream fires callbacks" {
    const allocator = std.testing.allocator;

    var events: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    defer events.deinit(allocator);

    stream_events = events;
    stream_alloc = allocator;

    const spec = runner.CommandSpec{
        .argv = &.{ "echo", "stream_test" },
    };

    const result = try runner.Runner.stream(allocator, spec, onStreamEvent);
    defer result.deinit();

    events = stream_events;

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("stdout", events.items[0][0]);
    try std.testing.expect(std.mem.indexOf(u8, events.items[0][1], "stream_test") != null);
}

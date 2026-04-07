const std = @import("std");
const runner = @import("runner");

pub fn buildPromptSpec(allocator: std.mem.Allocator, prompt: []const u8) !runner.CommandSpec {
    const trimmed = std.mem.trim(u8, prompt, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyPrompt;

    const argv = try allocator.alloc([]const u8, 3);
    argv[0] = "opencode";
    argv[1] = "run";
    argv[2] = try allocator.dupe(u8, trimmed);

    return .{ .argv = argv };
}

pub fn freePromptSpec(allocator: std.mem.Allocator, spec: runner.CommandSpec) void {
    allocator.free(spec.argv[2]);
    allocator.free(spec.argv);
}

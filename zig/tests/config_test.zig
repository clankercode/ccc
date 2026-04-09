const std = @import("std");
const config = @import("config");

test "loadConfig parses aliases and agent preset" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "config.toml";
    const file = try tmp.dir.createFile(path, .{});
    defer file.close();

    try file.writeAll(
        \\[defaults]
        \\runner = claude
        \\provider = anthropic
        \\model = opus
        \\thinking = 2
        \\
        \\[abbreviations]
        \\mycc = cc
        \\
        \\[aliases.work]
        \\runner = cc
        \\thinking = 3
        \\provider = anthropic
        \\model = claude-4
        \\agent = "reviewer"
        \\
    );

    const real_path = try tmp.dir.realpathAlloc(allocator, path);
    defer allocator.free(real_path);

    var parsed = try config.loadConfig(allocator, real_path);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("claude", parsed.default_runner);
    try std.testing.expectEqualStrings("anthropic", parsed.default_provider);
    try std.testing.expectEqualStrings("opus", parsed.default_model);
    try std.testing.expect(parsed.default_thinking != null);
    try std.testing.expectEqual(@as(i32, 2), parsed.default_thinking.?);
    try std.testing.expectEqualStrings("cc", parsed.abbreviations.get("mycc").?);

    const alias = parsed.aliases.get("work").?;
    try std.testing.expectEqualStrings("cc", alias.runner.?);
    try std.testing.expectEqual(@as(i32, 3), alias.thinking.?);
    try std.testing.expectEqualStrings("anthropic", alias.provider.?);
    try std.testing.expectEqualStrings("claude-4", alias.model.?);
    try std.testing.expectEqualStrings("reviewer", alias.agent.?);
}

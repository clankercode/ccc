const std = @import("std");
const parser = @import("parser");

test "parseArgs prompt-only" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "hello", "world" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.runner == null);
    try std.testing.expect(parsed.thinking == null);
    try std.testing.expect(parsed.provider == null);
    try std.testing.expect(parsed.model == null);
    try std.testing.expect(parsed.alias == null);
    try std.testing.expectEqualStrings("hello world", parsed.prompt);
}

test "parseArgs runner selector" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "claude", "do stuff" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.runner != null);
    try std.testing.expectEqualStrings("claude", parsed.runner.?);
    try std.testing.expectEqualStrings("do stuff", parsed.prompt);
}

test "parseArgs runner selector case insensitive" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "Claude", "do stuff" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.runner != null);
    try std.testing.expectEqualStrings("claude", parsed.runner.?);
}

test "parseArgs runner abbreviation" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "cc", "do stuff" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.runner != null);
    try std.testing.expectEqualStrings("cc", parsed.runner.?);
}

test "parseArgs thinking" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "+3", "think deeply" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.thinking != null);
    try std.testing.expectEqual(@as(i32, 3), parsed.thinking.?);
    try std.testing.expectEqualStrings("think deeply", parsed.prompt);
}

test "parseArgs thinking zero" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "+0", "no think" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(i32, 0), parsed.thinking.?);
}

test "parseArgs provider and model" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ ":openai:gpt-4", "prompt" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.provider != null);
    try std.testing.expectEqualStrings("openai", parsed.provider.?);
    try std.testing.expect(parsed.model != null);
    try std.testing.expectEqualStrings("gpt-4", parsed.model.?);
}

test "parseArgs model only" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ ":gpt-4o", "prompt" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.provider == null);
    try std.testing.expect(parsed.model != null);
    try std.testing.expectEqualStrings("gpt-4o", parsed.model.?);
}

test "parseArgs alias" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "@fast", "prompt" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.alias != null);
    try std.testing.expectEqualStrings("fast", parsed.alias.?);
}

test "parseArgs full combo" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "claude", "+2", ":anthropic:claude-3.5-sonnet", "@fast", "write code" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("claude", parsed.runner.?);
    try std.testing.expectEqual(@as(i32, 2), parsed.thinking.?);
    try std.testing.expectEqualStrings("anthropic", parsed.provider.?);
    try std.testing.expectEqualStrings("claude-3.5-sonnet", parsed.model.?);
    try std.testing.expectEqualStrings("fast", parsed.alias.?);
    try std.testing.expectEqualStrings("write code", parsed.prompt);
}

test "parseArgs positional after runner eats non-special" {
    const allocator = std.testing.allocator;
    const argv = &[_][]const u8{ "+3", "not+a", "flag" };
    var parsed = try parser.parseArgs(allocator, argv);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(i32, 3), parsed.thinking.?);
    try std.testing.expectEqualStrings("not+a flag", parsed.prompt);
}

test "resolveCommand default runner" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{"hello"});
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved.argv.len >= 3);
    try std.testing.expectEqualStrings("opencode", resolved.argv[0]);
    try std.testing.expectEqualStrings("run", resolved.argv[1]);
    try std.testing.expectEqualStrings("hello", resolved.argv[2]);
}

test "resolveCommand claude runner" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "claude", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expect(resolved.argv.len >= 2);
    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[1]);
}

test "resolveCommand thinking flags claude" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "claude", "+3", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("--thinking", resolved.argv[1]);
    try std.testing.expectEqualStrings("high", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
}

test "resolveCommand thinking flags kimi" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "kimi", "+0", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("kimi", resolved.argv[0]);
    try std.testing.expectEqualStrings("--no-think", resolved.argv[1]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[2]);
}

test "resolveCommand model flag" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "claude", ":gpt-4o", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("--model", resolved.argv[1]);
    try std.testing.expectEqualStrings("gpt-4o", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
}

test "resolveCommand provider env" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ ":openai:gpt-4", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    const provider = resolved.env.get("CCC_PROVIDER");
    try std.testing.expect(provider != null);
    try std.testing.expectEqualStrings("openai", provider.?);
}

test "resolveCommand empty prompt error" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{"claude"});
    defer parsed.deinit(allocator);

    const result = parser.resolveCommand(allocator, parsed, &config);
    try std.testing.expectError(error.EmptyPrompt, result);
}

test "resolveCommand alias runner override" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    try config.aliases.put("fast", .{
        .runner = "claude",
        .thinking = 1,
    });

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "@fast", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("--thinking", resolved.argv[1]);
    try std.testing.expectEqualStrings("low", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
}

test "resolveCommand name falls back to agent" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "@reviewer", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("opencode", resolved.argv[0]);
    try std.testing.expectEqualStrings("run", resolved.argv[1]);
    try std.testing.expectEqualStrings("--agent", resolved.argv[2]);
    try std.testing.expectEqualStrings("reviewer", resolved.argv[3]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[4]);
    try std.testing.expect(resolved.warnings.len == 0);
}

test "resolveCommand preset agent wins over name fallback" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    try config.aliases.put("reviewer", .{
        .agent = "specialist",
    });

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "@reviewer", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("opencode", resolved.argv[0]);
    try std.testing.expectEqualStrings("run", resolved.argv[1]);
    try std.testing.expectEqualStrings("--agent", resolved.argv[2]);
    try std.testing.expectEqualStrings("specialist", resolved.argv[3]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[4]);
    try std.testing.expect(resolved.warnings.len == 0);
}

test "resolveCommand claude agent flag" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "claude", "@reviewer", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("--agent", resolved.argv[1]);
    try std.testing.expectEqualStrings("reviewer", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
    try std.testing.expect(resolved.warnings.len == 0);
}

test "resolveCommand kimi agent flag" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "k", "@reviewer", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("kimi", resolved.argv[0]);
    try std.testing.expectEqualStrings("--agent", resolved.argv[1]);
    try std.testing.expectEqualStrings("reviewer", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
    try std.testing.expect(resolved.warnings.len == 0);
}

test "resolveCommand unsupported agent warns" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "rc", "@reviewer", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("codex", resolved.argv[0]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[1]);
    try std.testing.expect(resolved.warnings.len == 1);
    try std.testing.expectEqualStrings(
        "warning: runner codex does not support agents; ignoring @reviewer",
        resolved.warnings[0],
    );
}

test "resolveCommand default thinking from config" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();
    config.default_thinking = 4;

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "claude", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("--thinking", resolved.argv[1]);
    try std.testing.expectEqualStrings("max", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
}

test "resolveCommand codex with model" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "codex", ":gpt-4", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("codex", resolved.argv[0]);
    try std.testing.expectEqualStrings("--model", resolved.argv[1]);
    try std.testing.expectEqualStrings("gpt-4", resolved.argv[2]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[3]);
}

test "resolveCommand crush no model flag" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "crush", ":model-1", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("crush", resolved.argv[0]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[1]);
    try std.testing.expect(resolved.argv.len == 2);
}

test "resolveCommand abbreviation from config" {
    const allocator = std.testing.allocator;
    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    try config.abbreviations.put("oc", "claude");

    var parsed = try parser.parseArgs(allocator, &[_][]const u8{ "oc", "prompt" });
    defer parsed.deinit(allocator);

    var resolved = try parser.resolveCommand(allocator, parsed, &config);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("claude", resolved.argv[0]);
    try std.testing.expectEqualStrings("prompt", resolved.argv[1]);
}

test "runnerRegistry has all entries" {
    const allocator = std.testing.allocator;
    var registry = try parser.runnerRegistry(allocator);
    defer registry.deinit();

    try std.testing.expect(registry.get("opencode") != null);
    try std.testing.expect(registry.get("claude") != null);
    try std.testing.expect(registry.get("kimi") != null);
    try std.testing.expect(registry.get("codex") != null);
    try std.testing.expect(registry.get("crush") != null);
    try std.testing.expect(registry.get("oc") != null);
    try std.testing.expect(registry.get("cc") != null);
    try std.testing.expect(registry.get("c") != null);
    try std.testing.expect(registry.get("k") != null);
    try std.testing.expect(registry.get("rc") != null);
    try std.testing.expect(registry.get("cr") != null);

    const oc = registry.get("oc").?;
    const opencode = registry.get("opencode").?;
    try std.testing.expectEqualStrings(opencode.binary, oc.binary);
}

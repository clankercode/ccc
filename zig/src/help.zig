const std = @import("std");

pub const USAGE_TEXT =
    "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"";

pub const HELP_TEXT =
    \\ccc — call coding CLIs
    \\
    \\Usage:
    \\  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
    \\  ccc --help
    \\  ccc -h
    \\
    \\Slots (in order):
    \\  runner        Select which coding CLI to use (default: oc)
    \\                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
    \\  +thinking     Set thinking level: +0 (off) through +4 (max)
    \\  :provider:model  Override provider and model
    \\  @name         Use a named preset from config; if no preset exists, treat it as an agent
    \\
    \\Examples:
    \\  ccc "Fix the failing tests"
    \\  ccc oc "Refactor auth module"
    \\  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
    \\  ccc k +4 "Debug the parser"
    \\  ccc @reviewer "Audit the API boundary"
    \\  ccc codex "Write a unit test"
    \\
    \\Config:
    \\  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
    \\
;

const RunnerEntry = struct {
    name: []const u8,
    alias: []const u8,
};

const CANONICAL_RUNNERS = [_]RunnerEntry{
    .{ .name = "opencode", .alias = "oc" },
    .{ .name = "claude", .alias = "cc" },
    .{ .name = "kimi", .alias = "k" },
    .{ .name = "codex", .alias = "rc" },
    .{ .name = "crush", .alias = "cr" },
};

fn getVersion(allocator: std.mem.Allocator, binary: []const u8) ?[]u8 {
    const argv = [_][]const u8{ binary, "--version" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;
    defer _ = child.wait() catch {};

    const output = child.stdout.?.readToEndAlloc(allocator, 4096) catch return null;
    defer allocator.free(output);
    if (output.len == 0) return null;

    const version = if (std.mem.indexOfScalar(u8, output, '\n')) |nl| output[0..nl] else output;
    return allocator.dupe(u8, version) catch null;
}

fn hasOnPath(allocator: std.mem.Allocator, name: []const u8) bool {
    var child = std.process.Child.init(
        &[_][]const u8{ "which", name },
        allocator,
    );
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return false;
    const term = child.wait() catch return false;
    return term.Exited == 0;
}

fn runnerChecklist(allocator: std.mem.Allocator, file: std.fs.File) !void {
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    writer.interface.writeAll("Runners:\n") catch return;

    for (CANONICAL_RUNNERS) |entry| {
        const on_path = hasOnPath(allocator, entry.name);
        if (on_path) {
            if (getVersion(allocator, entry.name)) |version| {
                defer allocator.free(version);
                if (version.len > 0) {
                    writer.interface.print("  [+] {s:<10} ({s})  {s}\n", .{ entry.name, entry.name, version }) catch return;
                } else {
                    writer.interface.print("  [+] {s:<10} ({s})  found\n", .{ entry.name, entry.name }) catch return;
                }
            } else {
                writer.interface.print("  [+] {s:<10} ({s})  found\n", .{ entry.name, entry.name }) catch return;
            }
        } else {
            writer.interface.print("  [-] {s:<10} ({s})  not found\n", .{ entry.name, entry.name }) catch return;
        }
    }
}

pub fn printHelp(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    try stdout_file.writeAll(HELP_TEXT);
    try stdout_file.writeAll("\n");
    runnerChecklist(allocator, stdout_file) catch {};
}

pub fn printUsage(allocator: std.mem.Allocator) !void {
    const stderr_file = std.fs.File.stderr();
    try stderr_file.writeAll(USAGE_TEXT);
    try stderr_file.writeAll("\n");
    runnerChecklist(allocator, stderr_file) catch {};
}

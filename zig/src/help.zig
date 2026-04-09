const std = @import("std");

const HELP_TEXT =
    \\ccc — call coding CLIs
    \\
    \\Usage:
    \\  ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"
    \\  ccc --help
    \\  ccc -h
    \\
    \\Slots (in order):
    \\  runner        Select which coding CLI to use (default: oc)
    \\                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
    \\  +thinking     Set thinking level: +0 (off) through +4 (max)
    \\  :provider:model  Override provider and model
    \\  @alias        Use a named preset from config
    \\
    \\Examples:
    \\  ccc "Fix the failing tests"
    \\  ccc oc "Refactor auth module"
    \\  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
    \\  ccc k +4 "Debug the parser"
    \\  ccc codex "Write a unit test"
    \\
    \\Config:
    \\  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations
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

fn getVersion(allocator: std.mem.Allocator, binary: []const u8) []const u8 {
    const argv = [_][]const u8{ binary, "--version" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return "";
    defer _ = child.wait() catch {};

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(allocator);

    child.stdout.?.reader().readAllArrayList(&stdout_buf, 4096) catch return "";

    const output = stdout_buf.items;
    if (output.len == 0) return "";

    if (std.mem.indexOfScalar(u8, output, '\n')) |nl| {
        return output[0..nl];
    }
    return output;
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
    var writer_buf: [4096]u8 = undefined;
    var w = std.fs.File.Writer.init(file, &writer_buf);
    var io_writer = w.initInterface(&writer_buf);

    io_writer.writeAll("Runners:\n") catch return;

    for (CANONICAL_RUNNERS) |entry| {
        const on_path = hasOnPath(allocator, entry.name);
        if (on_path) {
            const version = getVersion(allocator, entry.name);
            if (version.len > 0) {
                io_writer.print("  [+] {s:<10} ({s})  {s}\n", .{ entry.name, entry.name, version }) catch return;
            } else {
                io_writer.print("  [+] {s:<10} ({s})  found\n", .{ entry.name, entry.name }) catch return;
            }
        } else {
            io_writer.print("  [-] {s:<10} ({s})  not found\n", .{ entry.name, entry.name }) catch return;
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
    try stderr_file.writeAll("usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n");
    runnerChecklist(allocator, stderr_file) catch {};
}

const std = @import("std");
const runner = @import("runner");
const parser = @import("parser");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.skip();

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    while (args_iter.next()) |arg| {
        try argv.append(arg);
    }

    if (argv.items.len == 0) {
        std.debug.print("usage: ccc [runner] [+thinking] [:provider:model] [:model] [@alias] <prompt>\n", .{});
        std.process.exit(1);
    }

    var config = parser.CccConfig.init(allocator);
    defer config.deinit();

    var parsed = parser.parseArgs(allocator, argv.items) catch {
        std.debug.print("failed to parse args\n", .{});
        std.process.exit(1);
    };
    defer parsed.deinit(allocator);

    var resolved = parser.resolveCommand(allocator, parsed, &config) catch {
        std.debug.print("prompt must not be empty\n", .{});
        std.process.exit(1);
    };
    defer resolved.deinit(allocator);

    const real_opencode = std.process.getEnvVarOwned(allocator, "CCC_REAL_OPENCODE") catch null;
    const effective_argv: []const []const u8 = blk: {
        if (real_opencode) |opencode_path| {
            var new_argv = try allocator.alloc([]const u8, resolved.argv.len);
            new_argv[0] = opencode_path;
            for (resolved.argv[1..], 0..) |arg, i| {
                new_argv[i + 1] = arg;
            }
            break :blk new_argv;
        }
        break :blk resolved.argv;
    };

    const result = try runner.Runner.run(allocator, .{ .argv = effective_argv });

    if (result.stdout_data.len > 0) {
        try std.fs.File.stdout().writeAll(result.stdout_data);
    }
    if (result.stderr_data.len > 0) {
        try std.fs.File.stderr().writeAll(result.stderr_data);
    }
    std.process.exit(result.exit_code);
}

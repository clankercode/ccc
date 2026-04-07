const std = @import("std");
const runner = @import("runner");
const prompt_spec = @import("prompt_spec");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.skip();

    const prompt = args_iter.next() orelse {
        std.debug.print("usage: ccc \"<Prompt>\"\n", .{});
        std.process.exit(1);
    };

    if (args_iter.next() != null) {
        std.debug.print("usage: ccc \"<Prompt>\"\n", .{});
        std.process.exit(1);
    }

    const spec = prompt_spec.buildPromptSpec(allocator, prompt) catch {
        std.debug.print("prompt must not be empty\n", .{});
        std.process.exit(1);
    };

    const real_opencode = std.process.getEnvVarOwned(allocator, "CCC_REAL_OPENCODE") catch null;
    const effective_argv: []const []const u8 = blk: {
        if (real_opencode) |opencode_path| {
            const argv = try allocator.alloc([]const u8, 3);
            argv[0] = opencode_path;
            argv[1] = spec.argv[1];
            argv[2] = spec.argv[2];
            break :blk argv;
        }
        break :blk spec.argv;
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

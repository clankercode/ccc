const std = @import("std");

pub const CommandSpec = struct {
    argv: []const []const u8,
    stdin_text: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};

pub const CompletedRun = struct {
    allocator: std.mem.Allocator,
    exit_code: u8,
    stdout_data: []const u8,
    stderr_data: []const u8,

    pub fn deinit(self: *const CompletedRun) void {
        self.allocator.free(self.stdout_data);
        self.allocator.free(self.stderr_data);
    }
};

pub const Runner = struct {
    const max_output: usize = 10 * 1024 * 1024;

    fn failResult(allocator: std.mem.Allocator, argv0: []const u8, err: anyerror) !CompletedRun {
        return CompletedRun{
            .allocator = allocator,
            .exit_code = 1,
            .stdout_data = try allocator.dupe(u8, ""),
            .stderr_data = std.fmt.allocPrint(allocator, "failed to start {s}: {s}\n", .{ argv0, @errorName(err) }) catch unreachable,
        };
    }

    pub fn run(allocator: std.mem.Allocator, spec: CommandSpec) !CompletedRun {
        var child = std.process.Child.init(spec.argv, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        if (spec.cwd) |cwd_path| {
            child.cwd = cwd_path;
        }

        child.spawn() catch |err| {
            return failResult(allocator, spec.argv[0], err);
        };

        if (spec.stdin_text) |text| {
            child.stdin.?.writeAll(text) catch {};
        }
        child.stdin.?.close();
        child.stdin = null;

        var stdout_buf: std.ArrayList(u8) = .empty;
        defer stdout_buf.deinit(allocator);
        var stderr_buf: std.ArrayList(u8) = .empty;
        defer stderr_buf.deinit(allocator);

        child.collectOutput(allocator, &stdout_buf, &stderr_buf, max_output) catch {};

        const term = child.wait() catch |err| {
            return failResult(allocator, spec.argv[0], err);
        };

        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        return CompletedRun{
            .allocator = allocator,
            .exit_code = exit_code,
            .stdout_data = try stdout_buf.toOwnedSlice(allocator),
            .stderr_data = try stderr_buf.toOwnedSlice(allocator),
        };
    }

    pub fn stream(allocator: std.mem.Allocator, spec: CommandSpec, on_event: *const fn ([]const u8, []const u8) void) !CompletedRun {
        const result = try run(allocator, spec);
        if (result.stdout_data.len > 0) on_event("stdout", result.stdout_data);
        if (result.stderr_data.len > 0) on_event("stderr", result.stderr_data);
        return result;
    }
};

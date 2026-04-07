const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runner_mod = b.createModule(.{
        .root_source_file = b.path("src/runner.zig"),
    });

    const prompt_spec_mod = b.createModule(.{
        .root_source_file = b.path("src/prompt_spec.zig"),
        .imports = &.{
            .{ .name = "runner", .module = runner_mod },
        },
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/ccc.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runner", .module = runner_mod },
            .{ .name = "prompt_spec", .module = prompt_spec_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "ccc",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/runner_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runner", .module = runner_mod },
            .{ .name = "prompt_spec", .module = prompt_spec_mod },
        },
    });

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

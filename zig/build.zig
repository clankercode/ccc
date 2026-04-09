const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runner_mod = b.createModule(.{
        .root_source_file = b.path("src/runner.zig"),
    });

    const parser_mod = b.createModule(.{
        .root_source_file = b.path("src/parser.zig"),
    });

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .imports = &.{
            .{ .name = "parser", .module = parser_mod },
        },
    });

    const help_mod = b.createModule(.{
        .root_source_file = b.path("src/help.zig"),
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
            .{ .name = "parser", .module = parser_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "help", .module = help_mod },
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

    const parser_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parser_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "parser", .module = parser_mod },
        },
    });

    const parser_tests = b.addTest(.{
        .root_module = parser_test_mod,
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);

    const config_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/config_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
        },
    });

    const config_tests = b.addTest(.{
        .root_module = config_test_mod,
    });
    const run_config_tests = b.addRunArtifact(config_tests);

    const help_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/help_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "help", .module = help_mod },
        },
    });

    const help_tests = b.addTest(.{
        .root_module = help_test_mod,
    });
    const run_help_tests = b.addRunArtifact(help_tests);

    const json_output_test_mod = b.createModule(.{
        .root_source_file = b.path("src/json_output.zig"),
        .target = target,
        .optimize = optimize,
    });

    const json_output_tests = b.addTest(.{
        .root_module = json_output_test_mod,
    });
    const run_json_output_tests = b.addRunArtifact(json_output_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_config_tests.step);
    test_step.dependOn(&run_help_tests.step);
    test_step.dependOn(&run_json_output_tests.step);

    const parser_test_step = b.step("test-parser", "Run parser unit tests");
    parser_test_step.dependOn(&run_parser_tests.step);

    const config_test_step = b.step("test-config", "Run config unit tests");
    config_test_step.dependOn(&run_config_tests.step);

    const help_test_step = b.step("test-help", "Run help unit tests");
    help_test_step.dependOn(&run_help_tests.step);
}

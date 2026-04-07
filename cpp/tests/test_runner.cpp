#include <ccc/build_prompt.hpp>
#include <ccc/runner.hpp>

#include <gtest/gtest.h>

#include <filesystem>
#include <string>
#include <vector>

TEST(Run, ReturnsCompletedResult) {
    Runner runner([](const CommandSpec& spec) -> CompletedRun {
        return CompletedRun{spec.argv, 0, "hello out", "hello err"};
    });
    auto result = runner.run(make_command_spec({"echo", "hi"}));
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.out_stdout, "hello out");
    EXPECT_EQ(result.out_stderr, "hello err");
    EXPECT_EQ(result.argv, (std::vector<std::string>{"echo", "hi"}));
}

TEST(Run, UsesStdinAndEnv) {
    std::string captured_stdin;
    std::string captured_env_val;
    std::filesystem::path captured_cwd;

    Runner runner([&](const CommandSpec& spec) -> CompletedRun {
        if (spec.stdin_text) captured_stdin = *spec.stdin_text;
        if (spec.env.count("MY_VAR")) captured_env_val = spec.env.at("MY_VAR");
        if (spec.cwd) captured_cwd = *spec.cwd;
        return CompletedRun{spec.argv, 0, "", ""};
    });

    auto spec = make_command_spec({"cmd"});
    with_stdin(spec, "input data");
    with_env(spec, "MY_VAR", "test_value");
    with_cwd(spec, "/tmp");

    runner.run(spec);
    EXPECT_EQ(captured_stdin, "input data");
    EXPECT_EQ(captured_env_val, "test_value");
    EXPECT_EQ(captured_cwd, "/tmp");
}

TEST(Stream, EmitsStdoutAndStderrEvents) {
    std::vector<std::pair<std::string, std::string>> events;

    Runner runner([](const CommandSpec& spec) -> CompletedRun {
        return CompletedRun{spec.argv, 42, "stdout data", "stderr data"};
    });

    auto on_event = [&events](std::string_view stream_name, std::string_view data) {
        events.emplace_back(std::string(stream_name), std::string(data));
    };

    auto result = runner.stream(make_command_spec({"cmd"}), on_event);
    EXPECT_EQ(result.exit_code, 42);

    ASSERT_EQ(events.size(), 2);
    EXPECT_EQ(events[0].first, "stdout");
    EXPECT_EQ(events[0].second, "stdout data");
    EXPECT_EQ(events[1].first, "stderr");
    EXPECT_EQ(events[1].second, "stderr data");
}

TEST(Run, ReportsMissingBinaryStartFailure) {
    Runner runner;
    auto spec = make_command_spec({"ccc_nonexistent_binary_xyz_12345"});
    auto result = runner.run(spec);
    EXPECT_NE(result.exit_code, 0);
    EXPECT_TRUE(result.out_stdout.empty());
    EXPECT_NE(result.out_stderr.find("failed to start"), std::string::npos);
    EXPECT_NE(result.out_stderr.find("ccc_nonexistent_binary_xyz_12345"), std::string::npos);
}

TEST(Stream, ReportsMissingBinaryStartFailure) {
    Runner runner;
    std::vector<std::pair<std::string, std::string>> events;
    auto on_event = [&events](std::string_view stream_name, std::string_view data) {
        events.emplace_back(std::string(stream_name), std::string(data));
    };

    auto spec = make_command_spec({"ccc_nonexistent_binary_xyz_12345"});
    auto result = runner.stream(spec, on_event);
    EXPECT_NE(result.exit_code, 0);

    bool has_stderr_event = false;
    for (const auto& [name, data] : events) {
        if (name == "stderr") {
            has_stderr_event = true;
            EXPECT_NE(data.find("failed to start"), std::string::npos);
        }
    }
    EXPECT_TRUE(has_stderr_event);
}

TEST(CommandSpec, HoldsFields) {
    auto spec = make_command_spec({"cmd", "arg1"});
    with_stdin(spec, "my input");
    with_env(spec, "KEY1", "val1");
    with_env(spec, "KEY2", "val2");
    with_cwd(spec, "/home/user");

    EXPECT_EQ(spec.argv, (std::vector<std::string>{"cmd", "arg1"}));
    ASSERT_TRUE(spec.stdin_text.has_value());
    EXPECT_EQ(*spec.stdin_text, "my input");
    ASSERT_TRUE(spec.cwd.has_value());
    EXPECT_EQ(*spec.cwd, "/home/user");
    EXPECT_EQ(spec.env.size(), 2);
    EXPECT_EQ(spec.env.at("KEY1"), "val1");
    EXPECT_EQ(spec.env.at("KEY2"), "val2");
}

TEST(BuildPromptSpec, ValidPrompt) {
    auto spec = build_prompt_spec("Fix the failing tests");
    ASSERT_TRUE(spec.has_value());
    EXPECT_EQ(spec->argv.size(), 3);
    EXPECT_EQ(spec->argv[0], "opencode");
    EXPECT_EQ(spec->argv[1], "run");
    EXPECT_EQ(spec->argv[2], "Fix the failing tests");
}

TEST(BuildPromptSpec, EmptyRejected) {
    EXPECT_FALSE(build_prompt_spec("").has_value());
}

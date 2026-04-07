#include <ccc/build_prompt.hpp>

#include <gtest/gtest.h>

#include <string>
#include <vector>

TEST(BuildPromptSpec, ReturnsValidSpec) {
    auto spec = build_prompt_spec("Fix the failing tests");
    ASSERT_TRUE(spec.has_value());
    const std::vector<std::string> expected_argv = {"opencode", "run", "Fix the failing tests"};
    EXPECT_EQ(spec->argv, expected_argv);
    EXPECT_FALSE(spec->stdin_text.has_value());
    EXPECT_FALSE(spec->cwd.has_value());
    EXPECT_TRUE(spec->env.empty());
}

TEST(BuildPromptSpec, RejectsEmpty) {
    auto spec = build_prompt_spec("");
    EXPECT_FALSE(spec.has_value());
}

TEST(BuildPromptSpec, RejectsWhitespace) {
    auto spec = build_prompt_spec("   ");
    EXPECT_FALSE(spec.has_value());
}

TEST(BuildPromptSpec, RejectsTabOnly) {
    auto spec = build_prompt_spec("\t\n");
    EXPECT_FALSE(spec.has_value());
}

TEST(BuildPromptSpec, TrimsLeading) {
    auto spec = build_prompt_spec("  hello  ");
    ASSERT_TRUE(spec.has_value());
    EXPECT_EQ(spec->argv[2], "hello");
}

TEST(BuildPromptSpec, TrimsTrailing) {
    auto spec = build_prompt_spec("hello   ");
    ASSERT_TRUE(spec.has_value());
    EXPECT_EQ(spec->argv[2], "hello");
}

TEST(BuildPromptSpec, TrimsMixedWhitespace) {
    auto spec = build_prompt_spec("\t  hello world  \n");
    ASSERT_TRUE(spec.has_value());
    EXPECT_EQ(spec->argv[2], "hello world");
}

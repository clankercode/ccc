#include <ccc/config.hpp>
#include <ccc/help.hpp>
#include <ccc/parser.hpp>

#include <gtest/gtest.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

class ParseArgsTest : public ::testing::Test {};

TEST_F(ParseArgsTest, PromptOnly) {
    auto p = parseArgs({"hello world"});
    EXPECT_EQ(p.prompt, "hello world");
    EXPECT_FALSE(p.runner.has_value());
    EXPECT_FALSE(p.thinking.has_value());
    EXPECT_FALSE(p.provider.has_value());
    EXPECT_FALSE(p.model.has_value());
    EXPECT_FALSE(p.alias.has_value());
}

TEST_F(ParseArgsTest, RunnerSelectorCc) {
    auto p = parseArgs({"cc", "fix bug"});
    EXPECT_EQ(p.runner, "cc");
    EXPECT_EQ(p.prompt, "fix bug");
}

TEST_F(ParseArgsTest, RunnerSelectorOpencode) {
    auto p = parseArgs({"opencode", "hello"});
    EXPECT_EQ(p.runner, "opencode");
    EXPECT_EQ(p.prompt, "hello");
}

TEST_F(ParseArgsTest, RunnerSelectorCodexAliasC) {
    auto p = parseArgs({"c", "fix bug"});
    EXPECT_EQ(p.runner, "c");
    EXPECT_EQ(p.prompt, "fix bug");
}

TEST_F(ParseArgsTest, RunnerSelectorCodexAliasCx) {
    auto p = parseArgs({"cx", "fix bug"});
    EXPECT_EQ(p.runner, "cx");
    EXPECT_EQ(p.prompt, "fix bug");
}

TEST_F(ParseArgsTest, RunnerSelectorRoocodeAliasRc) {
    auto p = parseArgs({"rc", "fix bug"});
    EXPECT_EQ(p.runner, "rc");
    EXPECT_EQ(p.prompt, "fix bug");
}

TEST_F(ParseArgsTest, ThinkingLevel) {
    auto p = parseArgs({"+2", "hello"});
    EXPECT_EQ(p.thinking, 2);
    EXPECT_EQ(p.prompt, "hello");
}

TEST_F(ParseArgsTest, ProviderModel) {
    auto p = parseArgs({":anthropic:claude-4", "hello"});
    EXPECT_EQ(p.provider, "anthropic");
    EXPECT_EQ(p.model, "claude-4");
    EXPECT_EQ(p.prompt, "hello");
}

TEST_F(ParseArgsTest, ModelOnly) {
    auto p = parseArgs({":gpt-4o", "hello"});
    EXPECT_EQ(p.model, "gpt-4o");
    EXPECT_FALSE(p.provider.has_value());
    EXPECT_EQ(p.prompt, "hello");
}

TEST_F(ParseArgsTest, Alias) {
    auto p = parseArgs({"@work", "hello"});
    EXPECT_EQ(p.alias, "work");
    EXPECT_EQ(p.prompt, "hello");
}

TEST_F(ParseArgsTest, FullCombo) {
    auto p = parseArgs({"cc", "+3", ":anthropic:claude-4", "@fast", "fix tests"});
    EXPECT_EQ(p.runner, "cc");
    EXPECT_EQ(p.thinking, 3);
    EXPECT_EQ(p.provider, "anthropic");
    EXPECT_EQ(p.model, "claude-4");
    EXPECT_EQ(p.alias, "fast");
    EXPECT_EQ(p.prompt, "fix tests");
}

TEST_F(ParseArgsTest, RunnerCaseInsensitive) {
    auto p = parseArgs({"CC", "hello"});
    EXPECT_EQ(p.runner, "cc");
}

TEST_F(ParseArgsTest, ThinkingZero) {
    auto p = parseArgs({"+0", "hello"});
    EXPECT_EQ(p.thinking, 0);
}

TEST_F(ParseArgsTest, ThinkingOutOfRangeNotMatched) {
    auto p = parseArgs({"+5", "hello"});
    EXPECT_FALSE(p.thinking.has_value());
    EXPECT_EQ(p.prompt, "+5 hello");
}

TEST_F(ParseArgsTest, TokensAfterPromptBecomePartOfPrompt) {
    auto p = parseArgs({"cc", "hello", "+2"});
    EXPECT_EQ(p.runner, "cc");
    EXPECT_EQ(p.prompt, "hello +2");
}

TEST_F(ParseArgsTest, MultiWordPrompt) {
    auto p = parseArgs({"fix", "the", "bug"});
    EXPECT_EQ(p.prompt, "fix the bug");
}

class HelpTest : public ::testing::Test {};

TEST_F(HelpTest, HelpTextUsesNameSlotAndFallback) {
    std::string help = HELP_TEXT;
    EXPECT_NE(help.find("[@name]"), std::string::npos);
    EXPECT_NE(help.find("if no preset exists, treat it as an agent"), std::string::npos);
    EXPECT_NE(help.find("claude (cc)"), std::string::npos);
    EXPECT_NE(help.find("codex (c/cx)"), std::string::npos);
    EXPECT_NE(help.find("roocode (rc)"), std::string::npos);
}

TEST_F(HelpTest, PrintUsageUsesNameSlot) {
    testing::internal::CaptureStderr();
    printUsage();
    std::string usage = testing::internal::GetCapturedStderr();
    EXPECT_NE(usage.find("[@name]"), std::string::npos);
}

class ResolveCommandTest : public ::testing::Test {};

TEST_F(ResolveCommandTest, DefaultRunnerIsOpencode) {
    ParsedArgs parsed;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "opencode");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "run"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "hello"), argv.end());
}

TEST_F(ResolveCommandTest, ClaudeRunner) {
    ParsedArgs parsed;
    parsed.runner = "cc";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "claude");
    EXPECT_EQ(std::find(argv.begin(), argv.end(), "run"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "hello"), argv.end());
}

TEST_F(ResolveCommandTest, CodexRunnerAliasC) {
    ParsedArgs parsed;
    parsed.runner = "c";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "codex");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "hello"), argv.end());
}

TEST_F(ResolveCommandTest, CodexRunnerAliasCx) {
    ParsedArgs parsed;
    parsed.runner = "cx";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "codex");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "hello"), argv.end());
}

TEST_F(ResolveCommandTest, RoocodeRunnerAliasRc) {
    ParsedArgs parsed;
    parsed.runner = "rc";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "roocode");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "hello"), argv.end());
}

TEST_F(ResolveCommandTest, ThinkingFlagsForClaude) {
    ParsedArgs parsed;
    parsed.runner = "cc";
    parsed.thinking = 2;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[1], "--thinking");
    EXPECT_EQ(argv[2], "enabled");
    EXPECT_EQ(argv[3], "--effort");
    EXPECT_EQ(argv[4], "medium");
}

TEST_F(ResolveCommandTest, ThinkingZeroForClaude) {
    ParsedArgs parsed;
    parsed.runner = "cc";
    parsed.thinking = 0;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[1], "--thinking");
    EXPECT_EQ(argv[2], "disabled");
}

TEST_F(ResolveCommandTest, ModelFlagForClaude) {
    ParsedArgs parsed;
    parsed.runner = "cc";
    parsed.model = "claude-4";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--model"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "claude-4"), argv.end());
}

TEST_F(ResolveCommandTest, ProviderSetsEnv) {
    ParsedArgs parsed;
    parsed.provider = "anthropic";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(env.at("CCC_PROVIDER"), "anthropic");
}

TEST_F(ResolveCommandTest, EmptyPromptThrows) {
    ParsedArgs parsed;
    parsed.prompt = "   ";
    EXPECT_THROW(resolveCommand(parsed), std::invalid_argument);
}

TEST_F(ResolveCommandTest, ConfigDefaultRunner) {
    CccConfig config;
    config.default_runner = "cc";
    ParsedArgs parsed;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[0], "claude");
}

TEST_F(ResolveCommandTest, ConfigDefaultThinking) {
    CccConfig config;
    config.default_runner = "cc";
    config.default_thinking = 1;
    ParsedArgs parsed;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[1], "--thinking");
    EXPECT_EQ(argv[2], "enabled");
    EXPECT_EQ(argv[3], "--effort");
    EXPECT_EQ(argv[4], "low");
}

TEST_F(ResolveCommandTest, ConfigDefaultModel) {
    CccConfig config;
    config.default_runner = "cc";
    config.default_model = "claude-3.5";
    ParsedArgs parsed;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--model"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "claude-3.5"), argv.end());
}

TEST_F(ResolveCommandTest, ConfigAbbreviation) {
    CccConfig config;
    config.abbreviations["mycc"] = "cc";
    ParsedArgs parsed;
    parsed.runner = "mycc";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[0], "claude");
}

TEST_F(ResolveCommandTest, AliasProvidesDefaults) {
    CccConfig config;
    AliasDef alias;
    alias.runner = "cc";
    alias.thinking = 3;
    alias.model = "claude-4";
    config.aliases["work"] = alias;
    ParsedArgs parsed;
    parsed.alias = "work";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[0], "claude");
    EXPECT_EQ(argv[1], "--thinking");
    EXPECT_EQ(argv[2], "enabled");
    EXPECT_EQ(argv[3], "--effort");
    EXPECT_EQ(argv[4], "high");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--model"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "claude-4"), argv.end());
}

TEST_F(ResolveCommandTest, ExplicitOverridesAlias) {
    CccConfig config;
    AliasDef alias;
    alias.runner = "cc";
    alias.thinking = 3;
    alias.model = "claude-4";
    config.aliases["work"] = alias;
    ParsedArgs parsed;
    parsed.runner = "k";
    parsed.alias = "work";
    parsed.thinking = 1;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[0], "kimi");
    EXPECT_EQ(argv[1], "--thinking");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--model"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "claude-4"), argv.end());
    EXPECT_EQ(std::find(argv.begin(), argv.end(), "--agent"), argv.end());
    EXPECT_EQ(std::find(argv.begin(), argv.end(), "specialist"), argv.end());
}

TEST_F(ResolveCommandTest, KimiThinkingFlags) {
    ParsedArgs parsed;
    parsed.runner = "k";
    parsed.thinking = 4;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[1], "--thinking");
}

TEST_F(ResolveCommandTest, KimiThinkingZero) {
    ParsedArgs parsed;
    parsed.runner = "k";
    parsed.thinking = 0;
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "kimi");
    EXPECT_EQ(argv[1], "--no-thinking");
}

TEST_F(ResolveCommandTest, UnknownNameFallsBackToAgentOnOpencode) {
    ParsedArgs parsed;
    parsed.alias = "reviewer";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "opencode");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--agent"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "reviewer"), argv.end());
    EXPECT_TRUE(warnings.empty());
}

TEST_F(ResolveCommandTest, PresetAgentAppliesWhenPresent) {
    CccConfig config;
    AliasDef alias;
    alias.agent = "specialist";
    config.aliases["reviewer"] = alias;
    ParsedArgs parsed;
    parsed.alias = "reviewer";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed, &config);
    EXPECT_EQ(argv[0], "opencode");
    EXPECT_NE(std::find(argv.begin(), argv.end(), "--agent"), argv.end());
    EXPECT_NE(std::find(argv.begin(), argv.end(), "specialist"), argv.end());
    EXPECT_TRUE(warnings.empty());
}

TEST_F(ResolveCommandTest, UnsupportedAgentWarnsAndIsIgnored) {
    ParsedArgs parsed;
    parsed.runner = "rc";
    parsed.alias = "reviewer";
    parsed.prompt = "hello";
    auto [argv, env, warnings] = resolveCommand(parsed);
    EXPECT_EQ(argv[0], "roocode");
    EXPECT_EQ(std::find(argv.begin(), argv.end(), "--agent"), argv.end());
    ASSERT_EQ(warnings.size(), 1u);
    EXPECT_NE(warnings[0].find("warning: runner \"rc\" does not support agents; ignoring @reviewer"),
              std::string::npos);
}

class RegistryTest : public ::testing::Test {};

TEST_F(RegistryTest, AllSelectorsRegistered) {
    const auto& reg = getRunnerRegistry();
    for (const auto& sel : {"oc", "cc", "c", "cx", "k", "rc", "cr",
                            "codex", "claude", "opencode", "kimi", "roocode", "crush"}) {
        EXPECT_NE(reg.find(sel), reg.end()) << "Missing selector: " << sel;
    }
}

TEST_F(RegistryTest, AbbreviationsShareBinary) {
    const auto& reg = getRunnerRegistry();
    EXPECT_EQ(reg.at("oc").binary, reg.at("opencode").binary);
    EXPECT_EQ(reg.at("cc").binary, reg.at("claude").binary);
    EXPECT_EQ(reg.at("c").binary, reg.at("codex").binary);
    EXPECT_EQ(reg.at("cx").binary, reg.at("codex").binary);
    EXPECT_EQ(reg.at("k").binary, reg.at("kimi").binary);
    EXPECT_EQ(reg.at("rc").binary, reg.at("roocode").binary);
}

TEST_F(RegistryTest, AgentFlagsAreRegisteredWhereSupported) {
    const auto& reg = getRunnerRegistry();
    EXPECT_EQ(reg.at("opencode").agent_flag, "--agent");
    EXPECT_EQ(reg.at("claude").agent_flag, "--agent");
    EXPECT_EQ(reg.at("kimi").agent_flag, "--agent");
    EXPECT_TRUE(reg.at("codex").agent_flag.empty());
    EXPECT_TRUE(reg.at("roocode").agent_flag.empty());
    EXPECT_TRUE(reg.at("crush").agent_flag.empty());
}

class LoadConfigTest : public ::testing::Test {};

TEST_F(LoadConfigTest, MissingFileReturnsDefaults) {
    auto config = loadConfig("/nonexistent/path/config.toml");
    EXPECT_EQ(config.default_runner, "oc");
    EXPECT_TRUE(config.aliases.empty());
}

TEST_F(LoadConfigTest, ValidTomlConfig) {
    std::string tmp = std::tmpnam(nullptr);
    {
        std::ofstream f(tmp);
        f << "[defaults]\n"
          << "runner = \"cc\"\n"
          << "provider = \"anthropic\"\n"
          << "model = \"claude-4\"\n"
          << "thinking = 2\n"
          << "\n"
          << "[abbreviations]\n"
          << "mycc = \"cc\"\n"
          << "\n"
          << "[aliases.work]\n"
          << "runner = \"cc\"\n"
          << "thinking = 3\n"
          << "model = \"claude-4\"\n"
          << "agent = \"reviewer\"\n"
          << "\n"
          << "[aliases.quick]\n"
          << "runner = \"oc\"\n";
    }
    auto config = loadConfig(tmp);
    std::remove(tmp.c_str());

    EXPECT_EQ(config.default_runner, "cc");
    EXPECT_EQ(config.default_provider, "anthropic");
    EXPECT_EQ(config.default_model, "claude-4");
    ASSERT_TRUE(config.default_thinking.has_value());
    EXPECT_EQ(config.default_thinking.value(), 2);
    EXPECT_EQ(config.abbreviations["mycc"], "cc");
    EXPECT_NE(config.aliases.find("work"), config.aliases.end());
    EXPECT_EQ(config.aliases["work"].runner, "cc");
    ASSERT_TRUE(config.aliases["work"].thinking.has_value());
    EXPECT_EQ(config.aliases["work"].thinking.value(), 3);
    EXPECT_EQ(config.aliases["work"].model, "claude-4");
    EXPECT_EQ(config.aliases["work"].agent, "reviewer");
    EXPECT_NE(config.aliases.find("quick"), config.aliases.end());
    EXPECT_EQ(config.aliases["quick"].runner, "oc");
}

TEST_F(LoadConfigTest, EmptyFileReturnsDefaults) {
    std::string tmp = std::tmpnam(nullptr);
    {
        std::ofstream f(tmp);
    }
    auto config = loadConfig(tmp);
    std::remove(tmp.c_str());
    EXPECT_EQ(config.default_runner, "oc");
}

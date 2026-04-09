#pragma once

#include <map>
#include <optional>
#include <tuple>
#include <string>
#include <utility>
#include <vector>

struct RunnerInfo {
    std::string binary;
    std::vector<std::string> extra_args;
    std::map<int, std::vector<std::string>> thinking_flags;
    std::string provider_flag;
    std::string model_flag;
    std::string agent_flag;
};

struct ParsedArgs {
    std::optional<std::string> runner;
    std::optional<int> thinking;
    std::optional<std::string> provider;
    std::optional<std::string> model;
    std::optional<std::string> alias;
    std::string prompt;
};

struct AliasDef {
    std::optional<std::string> runner;
    std::optional<int> thinking;
    std::optional<std::string> provider;
    std::optional<std::string> model;
    std::optional<std::string> agent;
};

struct CccConfig {
    std::string default_runner = "oc";
    std::string default_provider;
    std::string default_model;
    std::optional<int> default_thinking;
    std::map<std::string, AliasDef> aliases;
    std::map<std::string, std::string> abbreviations;
};

const std::map<std::string, RunnerInfo>& getRunnerRegistry();

ParsedArgs parseArgs(const std::vector<std::string>& argv);

std::tuple<std::vector<std::string>, std::map<std::string, std::string>, std::vector<std::string>>
resolveCommand(const ParsedArgs& parsed, const CccConfig* config = nullptr);

#include <ccc/parser.hpp>

#include <algorithm>
#include <cctype>
#include <regex>
#include <sstream>
#include <stdexcept>

static const std::map<std::string, RunnerInfo>& initRunnerRegistry() {
    static std::map<std::string, RunnerInfo> reg = [] {
        std::map<std::string, RunnerInfo> r;

        RunnerInfo opencode{"opencode", {"run"}, {}, "", ""};
        r["opencode"] = opencode;

        RunnerInfo claude{"claude", {},
                          {{0, {"--no-thinking"}},
                           {1, {"--thinking", "low"}},
                           {2, {"--thinking", "medium"}},
                           {3, {"--thinking", "high"}},
                           {4, {"--thinking", "max"}}},
                          "", "--model"};
        r["claude"] = claude;

        RunnerInfo kimi{"kimi", {},
                        {{0, {"--no-think"}},
                         {1, {"--think", "low"}},
                         {2, {"--think", "medium"}},
                         {3, {"--think", "high"}},
                         {4, {"--think", "max"}}},
                        "", "--model"};
        r["kimi"] = kimi;

        RunnerInfo codex{"codex", {}, {}, "", "--model"};
        r["codex"] = codex;

        RunnerInfo crush{"crush", {}, {}, "", ""};
        r["crush"] = crush;

        r["oc"] = r["opencode"];
        r["cc"] = r["claude"];
        r["c"] = r["claude"];
        r["k"] = r["kimi"];
        r["rc"] = r["codex"];
        r["cr"] = r["crush"];

        return r;
    }();
    return reg;
}

const std::map<std::string, RunnerInfo>& getRunnerRegistry() {
    return initRunnerRegistry();
}

static std::string toLower(const std::string& s) {
    std::string out = s;
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return out;
}

static bool isRunnerSelector(const std::string& token) {
    static const std::vector<std::string> selectors = {
        "oc", "cc", "c", "k", "rc", "cr",
        "codex", "claude", "opencode", "kimi", "roocode", "crush", "pi"};
    auto low = toLower(token);
    for (const auto& s : selectors) {
        if (low == s) return true;
    }
    return false;
}

static bool matchThinking(const std::string& token, int& level) {
    if (token.size() == 2 && token[0] == '+' && token[1] >= '0' && token[1] <= '4') {
        level = token[1] - '0';
        return true;
    }
    return false;
}

static bool matchProviderModel(const std::string& token,
                                std::string& provider,
                                std::string& model) {
    if (token.size() < 4 || token[0] != ':' || token[1] == ':') return false;
    auto second_colon = token.find(':', 1);
    if (second_colon == std::string::npos) return false;
    if (second_colon == token.size() - 1) return false;
    provider = token.substr(1, second_colon - 1);
    model = token.substr(second_colon + 1);
    for (char c : provider) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '-') return false;
    }
    for (char c : model) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '.' && c != '_' && c != '-') return false;
    }
    return true;
}

static bool matchModel(const std::string& token, std::string& model) {
    if (token.size() < 2 || token[0] != ':') return false;
    if (token.size() >= 2 && token[1] == ':') return false;
    model = token.substr(1);
    for (char c : model) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '.' && c != '_' && c != '-') return false;
    }
    return true;
}

static bool matchAlias(const std::string& token, std::string& alias) {
    if (token.size() < 2 || token[0] != '@') return false;
    alias = token.substr(1);
    for (char c : alias) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '-') return false;
    }
    return true;
}

ParsedArgs parseArgs(const std::vector<std::string>& argv) {
    ParsedArgs parsed;
    std::vector<std::string> positional;

    for (const auto& token : argv) {
        int level = 0;
        std::string provider, model, alias;

        if (isRunnerSelector(token) && !parsed.runner.has_value() && positional.empty()) {
            parsed.runner = toLower(token);
        } else if (matchThinking(token, level) && positional.empty()) {
            parsed.thinking = level;
        } else if (matchProviderModel(token, provider, model) && positional.empty()) {
            parsed.provider = std::move(provider);
            parsed.model = std::move(model);
        } else if (matchModel(token, model) && positional.empty()) {
            parsed.model = std::move(model);
        } else if (matchAlias(token, alias) && !parsed.alias.has_value() && positional.empty()) {
            parsed.alias = std::move(alias);
        } else {
            positional.push_back(token);
        }
    }

    std::ostringstream oss;
    for (size_t i = 0; i < positional.size(); ++i) {
        if (i > 0) oss << ' ';
        oss << positional[i];
    }
    parsed.prompt = oss.str();
    return parsed;
}

static std::string resolveRunnerName(const std::optional<std::string>& name,
                                      const CccConfig& config) {
    if (!name.has_value()) {
        return config.default_runner;
    }
    auto it = config.abbreviations.find(*name);
    if (it != config.abbreviations.end()) {
        return it->second;
    }
    return *name;
}

std::pair<std::vector<std::string>, std::map<std::string, std::string>>
resolveCommand(const ParsedArgs& parsed, const CccConfig* config_ptr) {
    CccConfig default_config;
    const CccConfig& config = config_ptr ? *config_ptr : default_config;

    const auto& registry = getRunnerRegistry();

    std::string runner_name = resolveRunnerName(parsed.runner, config);

    const RunnerInfo* info = nullptr;
    auto it = registry.find(runner_name);
    if (it != registry.end()) {
        info = &it->second;
    } else {
        auto def_it = registry.find(config.default_runner);
        if (def_it != registry.end()) {
            info = &def_it->second;
        } else {
            info = &registry.at("opencode");
        }
    }

    const AliasDef* alias_def = nullptr;
    if (parsed.alias.has_value()) {
        auto alias_it = config.aliases.find(*parsed.alias);
        if (alias_it != config.aliases.end()) {
            alias_def = &alias_it->second;
        }
    }

    std::string effective_runner_name = runner_name;
    if (alias_def && alias_def->runner.has_value() && !parsed.runner.has_value()) {
        effective_runner_name = resolveRunnerName(alias_def->runner, config);
        auto ri = registry.find(effective_runner_name);
        if (ri != registry.end()) {
            info = &ri->second;
        }
    }

    std::vector<std::string> argv;
    argv.push_back(info->binary);
    for (const auto& a : info->extra_args) {
        argv.push_back(a);
    }

    std::optional<int> effective_thinking = parsed.thinking;
    if (!effective_thinking.has_value() && alias_def && alias_def->thinking.has_value()) {
        effective_thinking = alias_def->thinking;
    }
    if (!effective_thinking.has_value()) {
        effective_thinking = config.default_thinking;
    }
    if (effective_thinking.has_value()) {
        auto tf_it = info->thinking_flags.find(*effective_thinking);
        if (tf_it != info->thinking_flags.end()) {
            for (const auto& f : tf_it->second) {
                argv.push_back(f);
            }
        }
    }

    std::optional<std::string> effective_provider = parsed.provider;
    if (!effective_provider.has_value() && alias_def && alias_def->provider.has_value()) {
        effective_provider = alias_def->provider;
    }
    if (!effective_provider.has_value() && !config.default_provider.empty()) {
        effective_provider = config.default_provider;
    }

    std::optional<std::string> effective_model = parsed.model;
    if (!effective_model.has_value() && alias_def && alias_def->model.has_value()) {
        effective_model = alias_def->model;
    }
    if (!effective_model.has_value() && !config.default_model.empty()) {
        effective_model = config.default_model;
    }

    if (effective_model.has_value() && !info->model_flag.empty()) {
        argv.push_back(info->model_flag);
        argv.push_back(*effective_model);
    }

    std::map<std::string, std::string> env_overrides;
    if (effective_provider.has_value()) {
        env_overrides["CCC_PROVIDER"] = *effective_provider;
    }

    std::string prompt = parsed.prompt;
    size_t start = prompt.find_first_not_of(" \t\n\r");
    size_t end = prompt.find_last_not_of(" \t\n\r");
    if (start == std::string::npos) {
        throw std::invalid_argument("prompt must not be empty");
    }
    prompt = prompt.substr(start, end - start + 1);

    argv.push_back(prompt);
    return {std::move(argv), std::move(env_overrides)};
}

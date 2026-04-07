#include <ccc/build_prompt.hpp>

#include <cctype>
#include <string>

std::optional<CommandSpec> build_prompt_spec(std::string_view prompt) {
    while (!prompt.empty() && std::isspace(static_cast<unsigned char>(prompt.front()))) {
        prompt.remove_prefix(1);
    }
    while (!prompt.empty() && std::isspace(static_cast<unsigned char>(prompt.back()))) {
        prompt.remove_suffix(1);
    }
    if (prompt.empty()) {
        return std::nullopt;
    }

    std::vector<std::string> argv;
    argv.reserve(3);
    argv.emplace_back("opencode");
    argv.emplace_back("run");
    argv.emplace_back(prompt);
    return CommandSpec{std::move(argv), std::nullopt, std::nullopt, {}};
}

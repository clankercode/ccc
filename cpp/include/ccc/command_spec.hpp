#pragma once

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

struct CommandSpec {
    std::vector<std::string> argv;
    std::optional<std::string> stdin_text;
    std::optional<std::filesystem::path> cwd;
    std::map<std::string, std::string> env;
};

inline CommandSpec make_command_spec(std::vector<std::string> argv) {
    return CommandSpec{std::move(argv), std::nullopt, std::nullopt, {}};
}

inline CommandSpec& with_stdin(CommandSpec& spec, std::string text) {
    spec.stdin_text = std::move(text);
    return spec;
}

inline CommandSpec& with_cwd(CommandSpec& spec, std::filesystem::path dir) {
    spec.cwd = std::move(dir);
    return spec;
}

inline CommandSpec& with_env(CommandSpec& spec, std::string key, std::string value) {
    spec.env[std::move(key)] = std::move(value);
    return spec;
}

#include <ccc/config.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;

static std::string trim(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

static std::string unquote(const std::string& s) {
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"') {
        return s.substr(1, s.size() - 2);
    }
    return s;
}

CccConfig loadConfig(const std::string& path) {
    CccConfig config;
    std::ifstream file(path);
    if (!file.is_open()) return config;

    std::string line;
    std::string section;
    std::string subkey;
    bool in_aliases = false;

    while (std::getline(file, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;

        if (line.front() == '[' && line.back() == ']') {
            std::string header = trim(line.substr(1, line.size() - 2));
            in_aliases = false;
            subkey.clear();

            if (header == "defaults") {
                section = "defaults";
            } else if (header == "abbreviations") {
                section = "abbreviations";
            } else if (header.compare(0, 8, "aliases.") == 0) {
                section = "aliases";
                subkey = header.substr(8);
                in_aliases = true;
            } else {
                section.clear();
            }
            continue;
        }

        auto eq = line.find('=');
        if (eq == std::string::npos) continue;

        std::string key = trim(line.substr(0, eq));
        std::string val = trim(line.substr(eq + 1));

        if (section == "defaults") {
            if (key == "runner") {
                config.default_runner = unquote(val);
            } else if (key == "provider") {
                config.default_provider = unquote(val);
            } else if (key == "model") {
                config.default_model = unquote(val);
            } else if (key == "thinking") {
                try {
                    config.default_thinking = std::stoi(unquote(val));
                } catch (...) {}
            }
        } else if (section == "abbreviations") {
            config.abbreviations[key] = unquote(val);
        } else if (in_aliases && !subkey.empty()) {
            AliasDef& alias = config.aliases[subkey];
            if (key == "runner") {
                alias.runner = unquote(val);
            } else if (key == "thinking") {
                try {
                    alias.thinking = std::stoi(unquote(val));
                } catch (...) {}
            } else if (key == "provider") {
                alias.provider = unquote(val);
            } else if (key == "model") {
                alias.model = unquote(val);
            } else if (key == "agent") {
                alias.agent = unquote(val);
            }
        }
    }

    return config;
}

CccConfig loadDefaultConfig() {
    std::string xdg;
    const char* xdg_env = std::getenv("XDG_CONFIG_HOME");
    if (xdg_env) xdg = xdg_env;

    std::vector<std::string> paths;
    if (!xdg.empty()) {
        paths.push_back(xdg + "/ccc/config.toml");
    }
    paths.push_back(fs::path(std::getenv("HOME") ? std::getenv("HOME") : "/tmp") /
                     ".config" / "ccc" / "config.toml");

    for (const auto& p : paths) {
        if (fs::exists(p)) {
            return loadConfig(p);
        }
    }

    return CccConfig();
}

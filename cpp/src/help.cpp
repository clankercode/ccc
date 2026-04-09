#include <ccc/help.hpp>
#include <ccc/parser.hpp>

#include <array>
#include <cstdio>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

static const char* const kHelpText =
    "ccc \xe2\x80\x94 call coding CLIs\n"
    "\n"
    "Usage:\n"
    "  ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n"
    "  ccc --help\n"
    "  ccc -h\n"
    "\n"
    "Slots (in order):\n"
    "  runner        Select which coding CLI to use (default: oc)\n"
    "                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)\n"
    "  +thinking     Set thinking level: +0 (off) through +4 (max)\n"
    "  :provider:model  Override provider and model\n"
    "  @alias        Use a named preset from config\n"
    "\n"
    "Examples:\n"
    "  ccc \"Fix the failing tests\"\n"
    "  ccc oc \"Refactor auth module\"\n"
    "  ccc cc +2 :anthropic:claude-sonnet-4-20250514 \"Add tests\"\n"
    "  ccc k +4 \"Debug the parser\"\n"
    "  ccc codex \"Write a unit test\"\n"
    "\n"
    "Config:\n"
    "  ~/.config/ccc/config.toml  \xe2\x80\x94 default runner, aliases, abbreviations\n"
    "\n";

const char* const HELP_TEXT = kHelpText;

static std::string getVersion(const std::string& binary) {
    std::string cmd = binary + " --version 2>/dev/null";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    std::array<char, 256> buf;
    std::string result;
    while (fgets(buf.data(), static_cast<int>(buf.size()), pipe) != nullptr) {
        result += buf.data();
        auto nl = result.find('\n');
        if (nl != std::string::npos) {
            result.resize(nl);
            break;
        }
    }
    int status = pclose(pipe);
    if (status != 0 || result.empty()) return "";
    return result;
}

std::string runnerChecklist() {
    static const std::vector<std::pair<std::string, std::string>> runners = {
        {"opencode", "oc"},
        {"claude", "cc"},
        {"kimi", "k"},
        {"codex", "rc"},
        {"crush", "cr"},
    };

    const auto& registry = getRunnerRegistry();

    std::ostringstream oss;
    oss << "Runners:\n";
    for (const auto& [name, alias] : runners) {
        std::string binary = name;
        auto it = registry.find(name);
        if (it != registry.end()) {
            binary = it->second.binary;
        }
        if (auto fp = popen(("command -v " + binary + " 2>/dev/null").c_str(), "r")) {
            pclose(fp);
            std::string version = getVersion(binary);
            std::string tag = version.empty() ? "found" : version;
            oss << "  [+] " << name;
            for (size_t i = name.size(); i < 10; ++i) oss << ' ';
            oss << "(" << binary << ")  " << tag << "\n";
        } else {
            oss << "  [-] " << name;
            for (size_t i = name.size(); i < 10; ++i) oss << ' ';
            oss << "(" << binary << ")  not found\n";
        }
    }
    return oss.str();
}

void printHelp() {
    std::cout << HELP_TEXT << "\n" << runnerChecklist();
}

void printUsage() {
    std::cerr << "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n";
    std::cerr << runnerChecklist();
}

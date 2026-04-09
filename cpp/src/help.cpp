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
    "  ccc [controls...] \"<Prompt>\"\n"
    "  ccc --help\n"
    "  ccc -h\n"
    "\n"
    "Slots (in order):\n"
    "  runner        Select which coding CLI to use (default: oc)\n"
    "                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)\n"
    "  +thinking     Set thinking level: +0 (off) through +4 (max)\n"
    "  :provider:model  Override provider and model\n"
    "  @name         Use a named preset from config; if no preset exists, treat it as an agent\n"
    "\n"
    "Examples:\n"
    "  ccc \"Fix the failing tests\"\n"
    "  ccc oc \"Refactor auth module\"\n"
    "  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer \"Add tests\"\n"
    "  ccc c +4 :openai:gpt-5.4-mini @agent \"Debug the parser\"\n"
    "  ccc k +4 \"Debug the parser\"\n"
    "  ccc @reviewer \"Audit the API boundary\"\n"
    "  ccc c \"Write a unit test\"\n"
    "\n"
    "Config:\n"
    "  ~/.config/ccc/config.toml  \xe2\x80\x94 default runner, presets, abbreviations\n"
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

static bool isOnPath(const std::string& binary) {
    std::string cmd = "command -v " + binary + " >/dev/null 2>&1";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return false;
    int status = pclose(pipe);
    return status == 0;
}

std::string runnerChecklist() {
    static const std::vector<std::pair<std::string, std::string>> runners = {
        {"opencode", "oc"},
        {"claude", "cc"},
        {"kimi", "k"},
        {"codex", "c/cx"},
        {"roocode", "rc"},
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
        if (isOnPath(binary)) {
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
    std::cerr << "usage: ccc [controls...] \"<Prompt>\"\n";
    std::cerr << runnerChecklist();
}

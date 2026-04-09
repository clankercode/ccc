module call_coding_clis.help;

import std.stdio;
import std.process;
import std.string;
import std.format;

import call_coding_clis.parser : getRunnerRegistry;

enum HELP_TEXT =
`ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
`;

enum USAGE_TEXT = `usage: ccc [controls...] "<Prompt>"`;

private struct RunnerEntry {
    string name;
    string binary;
}

private RunnerEntry[] canonicalRunners() {
    auto registry = getRunnerRegistry();
    return [
        RunnerEntry("opencode", registry["opencode"].binary),
        RunnerEntry("claude", registry["claude"].binary),
        RunnerEntry("kimi", registry["kimi"].binary),
        RunnerEntry("codex", registry["codex"].binary),
        RunnerEntry("roocode", registry["roocode"].binary),
        RunnerEntry("crush", registry["crush"].binary),
    ];
}

private struct RunnerStatus {
    bool found;
    string ver;
}

private RunnerStatus checkRunner(string binary) {
    try {
        auto result = execute([binary, "--version"]);
        if (result.status == 0) {
            auto stdout_ = result.output.strip;
            if (stdout_.length > 0) {
                auto ver = stdout_.split("\n")[0];
                return RunnerStatus(true, ver);
            }
            return RunnerStatus(true, "");
        }
        return RunnerStatus(true, "");
    } catch (ProcessException) {
        return RunnerStatus(false, "");
    }
}

string runnerChecklist() {
    auto runners = canonicalRunners();
    string result = "Runners:";
    foreach (ref entry; runners) {
        auto status = checkRunner(entry.binary);
        if (status.found) {
            auto tag = status.ver.length > 0 ? status.ver : "found";
            result ~= format("\n  [+] %-10s (%s)  %s", entry.name, entry.binary, tag);
        } else {
            result ~= format("\n  [-] %-10s (%s)  not found", entry.name, entry.binary);
        }
    }
    return result;
}

void printHelp() {
    write(HELP_TEXT);
    writeln();
    writeln(runnerChecklist());
}

void printUsage() {
    stderr.writeln(USAGE_TEXT);
    stderr.writeln(runnerChecklist());
}

unittest {
    assert(HELP_TEXT.indexOf("@name") >= 0);
    assert(HELP_TEXT.indexOf("named preset from config; if no preset exists, treat it as an agent") >= 0);
    assert(HELP_TEXT.indexOf("codex (c/cx), roocode (rc), crush (cr)") >= 0);
    assert(USAGE_TEXT.indexOf("[@name]") >= 0);
}

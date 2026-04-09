module call_coding_clis.parser;

import std.typecons : Nullable;
import std.regex;
import std.string : toLower, strip, join, indexOf;
import std.conv : to, ConvException;
import std.array : appender;

struct RunnerInfo {
    string binary;
    string[] extraArgs;
    string[][int] thinkingFlags;
    string providerFlag;
    string modelFlag;
    string agentFlag;
}

struct ParsedArgs {
    Nullable!string runner;
    Nullable!int thinking;
    Nullable!string provider;
    Nullable!string model;
    Nullable!string aliasName;
    string prompt;
}

struct AliasDef {
    Nullable!string runner;
    Nullable!int thinking;
    Nullable!string provider;
    Nullable!string model;
    Nullable!string agent;
}

struct CccConfig {
    string defaultRunner = "oc";
    string defaultProvider;
    string defaultModel;
    Nullable!int defaultThinking;
    AliasDef[string] aliases;
    string[string] abbreviations;
}

private RunnerInfo[string] registry_;
private bool registryInitialized_;

private void ensureRegistry() {
    if (registryInitialized_) return;
    registryInitialized_ = true;

    auto opencode = RunnerInfo("opencode", ["run"], null, "", "", "--agent");
    auto claude = RunnerInfo("claude", null, [
        0: ["--no-thinking"],
        1: ["--thinking", "low"],
        2: ["--thinking", "medium"],
        3: ["--thinking", "high"],
        4: ["--thinking", "max"],
    ], "", "--model", "--agent");
    auto kimi = RunnerInfo("kimi", null, [
        0: ["--no-think"],
        1: ["--think", "low"],
        2: ["--think", "medium"],
        3: ["--think", "high"],
        4: ["--think", "max"],
    ], "", "--model", "--agent");
    auto codex = RunnerInfo("codex", null, null, "", "--model", "");
    auto crush = RunnerInfo("crush", null, null, "", "", "");

    registry_["opencode"] = opencode;
    registry_["claude"] = claude;
    registry_["kimi"] = kimi;
    registry_["codex"] = codex;
    registry_["crush"] = crush;

    registry_["oc"] = opencode;
    registry_["cc"] = claude;
    registry_["c"] = claude;
    registry_["k"] = kimi;
    registry_["rc"] = codex;
    registry_["cr"] = crush;
}

RunnerInfo[string] getRunnerRegistry() {
    ensureRegistry();
    return registry_;
}

private auto runnerSelectorRe() {
    static auto re = regex(
        `^(?:oc|cc|c|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$`, "i");
    return re;
}

private auto thinkingRe() {
    static auto re = regex(`^\+([0-4])$`);
    return re;
}

private auto providerModelRe() {
    static auto re = regex(`^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$`);
    return re;
}

private auto modelRe() {
    static auto re = regex(`^:([a-zA-Z0-9._-]+)$`);
    return re;
}

private auto aliasRe() {
    static auto re = regex(`^@([a-zA-Z0-9_-]+)$`);
    return re;
}

ParsedArgs parseArgs(string[] argv) {
    ParsedArgs parsed;
    string[] positional;

    foreach (token; argv) {
        if (!parsed.runner.isNull && positional.length > 0) {
            positional ~= token;
            continue;
        }

        if (match(token, runnerSelectorRe()) && parsed.runner.isNull && positional.length == 0) {
            parsed.runner = token.toLower();
        } else if (auto m = match(token, thinkingRe())) {
            if (positional.length == 0) {
                parsed.thinking = to!int(m.captures[1]);
            } else {
                positional ~= token;
            }
        } else if (auto m = match(token, providerModelRe())) {
            if (positional.length == 0) {
                parsed.provider = m.captures[1];
                parsed.model = m.captures[2];
            } else {
                positional ~= token;
            }
        } else if (auto m = match(token, modelRe())) {
            if (positional.length == 0) {
                parsed.model = m.captures[1];
            } else {
                positional ~= token;
            }
        } else if (auto m = match(token, aliasRe())) {
            if (parsed.aliasName.isNull && positional.length == 0) {
                parsed.aliasName = m.captures[1];
            } else {
                positional ~= token;
            }
        } else {
            positional ~= token;
        }
    }

    parsed.prompt = positional.join(" ");
    return parsed;
}

private string resolveRunnerName(Nullable!string name, ref CccConfig config) {
    if (name.isNull) {
        return config.defaultRunner;
    }
    auto n = name.get;
    if (auto p = n in config.abbreviations) {
        return *p;
    }
    return n;
}

struct ResolvedCommand {
    string[] argv;
    string[string] env;
    string[] warnings;
}

ResolvedCommand resolveCommand(ref ParsedArgs parsed, CccConfig config) {
    ensureRegistry();

    auto runnerName = resolveRunnerName(parsed.runner, config);

    auto infoPtr = runnerName in registry_;
    RunnerInfo info;
    if (infoPtr !is null) {
        info = *infoPtr;
    } else {
        auto defaultPtr = config.defaultRunner in registry_;
        if (defaultPtr !is null) {
            info = *defaultPtr;
        } else {
            info = registry_["opencode"];
        }
    }

    AliasDef* aliasDef;
    if (!parsed.aliasName.isNull) {
        auto p = parsed.aliasName.get in config.aliases;
        if (p !is null) {
            aliasDef = p;
        }
    }

    auto effectiveRunnerName = runnerName;
    if (aliasDef !is null && !aliasDef.runner.isNull && parsed.runner.isNull) {
        effectiveRunnerName = resolveRunnerName(aliasDef.runner, config);
        auto ep = effectiveRunnerName in registry_;
        if (ep !is null) {
            info = *ep;
        }
    }

    auto argv = appender!(string[]);
    argv ~= info.binary;
    argv ~= info.extraArgs;

    Nullable!int effectiveThinking = parsed.thinking;
    if (effectiveThinking.isNull && aliasDef !is null && !aliasDef.thinking.isNull) {
        effectiveThinking = aliasDef.thinking;
    }
    if (effectiveThinking.isNull) {
        effectiveThinking = config.defaultThinking;
    }
    if (!effectiveThinking.isNull) {
        auto lvl = effectiveThinking.get;
        if (auto flags = lvl in info.thinkingFlags) {
            argv ~= *flags;
        }
    }

    Nullable!string effectiveProvider = parsed.provider;
    if (effectiveProvider.isNull && aliasDef !is null && !aliasDef.provider.isNull) {
        effectiveProvider = aliasDef.provider;
    }
    if (effectiveProvider.isNull) {
        effectiveProvider = Nullable!string(config.defaultProvider);
    }

    Nullable!string effectiveModel = parsed.model;
    if (effectiveModel.isNull && aliasDef !is null && !aliasDef.model.isNull) {
        effectiveModel = aliasDef.model;
    }
    if (effectiveModel.isNull) {
        effectiveModel = Nullable!string(config.defaultModel);
    }

    if (!effectiveModel.isNull && effectiveModel.get.length > 0 && info.modelFlag.length > 0) {
        argv ~= info.modelFlag;
        argv ~= effectiveModel.get;
    }

    string[] warnings;

    Nullable!string requestedAgent;
    if (!parsed.aliasName.isNull && aliasDef is null) {
        requestedAgent = parsed.aliasName;
    }

    Nullable!string effectiveAgent = requestedAgent;
    if (effectiveAgent.isNull && aliasDef !is null && !aliasDef.agent.isNull) {
        effectiveAgent = aliasDef.agent;
    }
    if (!effectiveAgent.isNull && effectiveAgent.get.length > 0) {
        if (info.agentFlag.length > 0) {
            argv ~= info.agentFlag;
            argv ~= effectiveAgent.get;
        } else {
            warnings ~= "warning: runner \"" ~ effectiveRunnerName ~ "\" does not support agents; ignoring @" ~ effectiveAgent.get;
        }
    }

    string[string] envOverrides;
    if (!effectiveProvider.isNull && effectiveProvider.get.length > 0) {
        envOverrides["CCC_PROVIDER"] = effectiveProvider.get;
    }

    auto prompt = parsed.prompt.strip;
    if (prompt.length == 0) {
        throw new Exception("prompt must not be empty");
    }

    argv ~= prompt;

    return ResolvedCommand(argv.data, envOverrides, warnings);
}

unittest {
    auto reg = getRunnerRegistry();
    assert(reg["opencode"].agentFlag == "--agent");
    assert(reg["claude"].agentFlag == "--agent");
    assert(reg["kimi"].agentFlag == "--agent");
    assert(reg["codex"].agentFlag.length == 0);
    assert(reg["crush"].agentFlag.length == 0);
}

unittest {
    auto parsed = parseArgs(["@reviewer", "task"]);
    auto r = resolveCommand(parsed, CccConfig());
    assert(r.argv[0] == "opencode");
    assert(r.argv[1] == "run");
    assert(r.argv[2] == "--agent");
    assert(r.argv[3] == "reviewer");
    assert(r.argv[$ - 1] == "task");
    assert(r.warnings.length == 0);
}

unittest {
    auto parsed = parseArgs(["rc", "@reviewer", "task"]);
    auto r = resolveCommand(parsed, CccConfig());
    assert(r.argv[0] == "codex");
    assert(r.argv[$ - 1] == "task");
    assert(r.warnings.length == 1);
    assert(r.warnings[0] == "warning: runner \"rc\" does not support agents; ignoring @reviewer");
}

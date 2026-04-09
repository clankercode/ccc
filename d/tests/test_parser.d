module test_parser;

import std.stdio;
import std.exception;
import std.conv;

import call_coding_clis.parser : parseArgs, resolveCommand, CccConfig, AliasDef,
    ParsedArgs, getRunnerRegistry, RunnerInfo, ResolvedCommand;
import call_coding_clis.config : loadConfig;

private CccConfig defaultConfig() {
    return CccConfig();
}

unittest {
    auto p = parseArgs(["hello world"]);
    assert(p.runner.isNull);
    assert(p.thinking.isNull);
    assert(p.provider.isNull);
    assert(p.model.isNull);
    assert(p.aliasName.isNull);
    assert(p.prompt == "hello world");
}

unittest {
    auto p = parseArgs(["claude", "do stuff"]);
    assert(p.runner.get == "claude");
    assert(p.prompt == "do stuff");
}

unittest {
    auto p = parseArgs(["cc", "fix bug"]);
    assert(p.runner.get == "cc");
    assert(p.prompt == "fix bug");
}

unittest {
    auto p = parseArgs(["+3", "think hard"]);
    assert(p.thinking.get == 3);
    assert(p.prompt == "think hard");
}

unittest {
    auto p = parseArgs([":anthropic:claude-sonnet-4", "query"]);
    assert(p.provider.get == "anthropic");
    assert(p.model.get == "claude-sonnet-4");
    assert(p.prompt == "query");
}

unittest {
    auto p = parseArgs([":gpt-4o", "query"]);
    assert(p.provider.isNull);
    assert(p.model.get == "gpt-4o");
    assert(p.prompt == "query");
}

unittest {
    auto p = parseArgs(["@work", "do it"]);
    assert(p.aliasName.get == "work");
    assert(p.prompt == "do it");
}

unittest {
    auto p = parseArgs(["claude", "+2", ":anthropic:claude-sonnet-4", "complex task"]);
    assert(p.runner.get == "claude");
    assert(p.thinking.get == 2);
    assert(p.provider.get == "anthropic");
    assert(p.model.get == "claude-sonnet-4");
    assert(p.prompt == "complex task");
}

unittest {
    auto p = parseArgs(["+0", "hello"]);
    assert(p.thinking.get == 0);
    assert(p.prompt == "hello");
}

unittest {
    auto p = parseArgs(["+4", "max think"]);
    assert(p.thinking.get == 4);
}

unittest {
    auto parsed = parseArgs(["cc", "still claude"]);
    auto r = resolveCommand(parsed, defaultConfig());
    assert(r.argv[0] == "claude");
    assert(r.argv[$ - 1] == "still claude");
}

unittest {
    auto parsed = parseArgs(["c", "use codex"]);
    auto r = resolveCommand(parsed, defaultConfig());
    assert(r.argv[0] == "codex");
    assert(r.argv[1] == "exec");
    assert(r.argv[$ - 1] == "use codex");
}

unittest {
    auto parsed = parseArgs(["cx", "use codex"]);
    auto r = resolveCommand(parsed, defaultConfig());
    assert(r.argv[0] == "codex");
    assert(r.argv[1] == "exec");
    assert(r.argv[$ - 1] == "use codex");
}

unittest {
    auto parsed = parseArgs(["rc", "use roocode"]);
    auto r = resolveCommand(parsed, defaultConfig());
    assert(r.argv[0] == "roocode");
    assert(r.argv[$ - 1] == "use roocode");
}

unittest {
    auto reg = getRunnerRegistry();
    assert("opencode" in reg);
    assert("claude" in reg);
    assert("kimi" in reg);
    assert("codex" in reg);
    assert("roocode" in reg);
    assert("crush" in reg);
    assert("oc" in reg);
    assert("cc" in reg);
    assert("c" in reg);
    assert("cx" in reg);
    assert("k" in reg);
    assert("rc" in reg);
    assert("cr" in reg);
    assert(reg["opencode"].binary == "opencode");
    assert(reg["claude"].binary == "claude");
    assert(reg["codex"].binary == "codex");
    assert(reg["roocode"].binary == "roocode");
    assert(reg["opencode"].agentFlag == "--agent");
    assert(reg["claude"].agentFlag == "--agent");
    assert(reg["kimi"].agentFlag == "--agent");
    assert(reg["codex"].agentFlag.length == 0);
    assert(reg["roocode"].agentFlag.length == 0);
    assert(reg["crush"].agentFlag.length == 0);
    assert(reg["c"].binary == "codex");
    assert(reg["cx"].binary == "codex");
    assert(reg["rc"].binary == "roocode");
    assert(reg["cc"].binary == "claude");
}

unittest {
    auto reg = getRunnerRegistry();
    assert(reg["opencode"].binary == "opencode");
    assert(reg["opencode"].extraArgs == ["run"]);
    assert(reg["claude"].binary == "claude");
    assert(reg["claude"].modelFlag == "--model");
    assert(0 in reg["claude"].thinkingFlags);
    assert(3 in reg["claude"].thinkingFlags);
}

unittest {
    auto p = parseArgs(["just a prompt"]);
    assert(p.runner.isNull);
    assert(p.prompt == "just a prompt");
}

unittest {
    auto parsed = parseArgs(["hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "opencode");
    assert(r.argv[1] == "run");
    assert(r.argv[$ - 1] == "hello");
    assert(r.env.length == 0);
}

unittest {
    auto parsed = parseArgs(["claude", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[$ - 1] == "hello");
}

unittest {
    auto parsed = parseArgs(["claude", "+3", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[1] == "--thinking");
    assert(r.argv[2] == "high");
    assert(r.argv[$ - 1] == "hello");
}

unittest {
    auto parsed = parseArgs(["claude", "+0", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[1] == "--no-thinking");
}

unittest {
    auto parsed = parseArgs(["claude", ":gpt-4o", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[1] == "--model");
    assert(r.argv[2] == "gpt-4o");
}

unittest {
    auto parsed = parseArgs(["codex", ":openai:gpt-4o", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "codex");
    assert(r.argv[1] == "exec");
    assert(r.argv[2] == "--model");
    assert(r.argv[3] == "gpt-4o");
    assert("CCC_PROVIDER" in r.env);
    assert(r.env["CCC_PROVIDER"] == "openai");
}

unittest {
    auto parsed = parseArgs(["", "  "]);
    auto config = defaultConfig();
    assertThrown!Exception(resolveCommand(parsed, config));
}

unittest {
    auto config = CccConfig();
    config.aliases["work"] = AliasDef(
        Nullable!string("claude"),
        Nullable!int(2),
        Nullable!string("anthropic"),
        Nullable!string("claude-sonnet-4"),
        Nullable!string("reviewer")
    );
    auto parsed = parseArgs(["@work", "task"]);
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[1] == "--thinking");
    assert(r.argv[2] == "medium");
    assert(r.argv[3] == "--model");
    assert(r.argv[4] == "claude-sonnet-4");
    assert(r.argv[5] == "--agent");
    assert(r.argv[6] == "reviewer");
    assert(r.env["CCC_PROVIDER"] == "anthropic");
    assert(r.argv[$ - 1] == "task");
    assert(r.warnings.length == 0);
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
    assert(r.argv[0] == "roocode");
    assert(r.argv[$ - 1] == "task");
    assert(r.warnings.length == 1);
    assert(r.warnings[0] == "warning: runner \"roocode\" does not support agents; ignoring @reviewer");
}

unittest {
    auto config = CccConfig();
    config.abbreviations["myc"] = "claude";
    auto parsed = parseArgs(["myc", "hello"]);
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
}

unittest {
    auto parsed = parseArgs(["opencode", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "opencode");
    assert(r.argv[1] == "run");
}

unittest {
    auto config = CccConfig("claude", "", "", Nullable!int.init, null, null);
    auto parsed = parseArgs(["hello"]);
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
}

unittest {
    auto config = CccConfig("oc", "anthropic", "gpt-4o", Nullable!int(2), null, null);
    auto parsed = parseArgs(["hello"]);
    auto r = resolveCommand(parsed, config);
    assert("CCC_PROVIDER" in r.env);
    assert(r.env["CCC_PROVIDER"] == "anthropic");
    bool foundModel;
    foreach (i, a; r.argv) {
        if (a == "--model" && i + 1 < r.argv.length && r.argv[i + 1] == "gpt-4o") {
            foundModel = true;
        }
    }
    assert(foundModel || r.argv[$ - 2] == "--model");
}

unittest {
    auto parsed = parseArgs(["claude", "+2", ":openai:gpt-4o", "full test"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "claude");
    assert(r.argv[1] == "--thinking");
    assert(r.argv[2] == "medium");
    assert(r.argv[3] == "--model");
    assert(r.argv[4] == "gpt-4o");
    assert(r.argv[5] == "full test");
    assert(r.env["CCC_PROVIDER"] == "openai");
}

unittest {
    import std.stdio : File;
    import std.path : tempDir;
    import std.file : exists, remove;

    auto tmpPath = tempDir ~ "/ccc_test_config.toml";
    {
        auto f = File(tmpPath, "w");
        f.writeln(`[defaults]`);
        f.writeln(`runner = "claude"`);
        f.writeln(`provider = "anthropic"`);
        f.writeln(`model = "claude-sonnet-4"`);
        f.writeln(`thinking = 3`);
        f.writeln;
        f.writeln(`[abbreviations]`);
        f.writeln(`myc = "claude"`);
        f.writeln;
        f.writeln(`[aliases.work]`);
        f.writeln(`runner = "oc"`);
        f.writeln(`thinking = 1`);
        f.writeln(`agent = "reviewer"`);
        f.close();
    }

    auto config = loadConfig(tmpPath);
    assert(config.defaultRunner == "claude");
    assert(config.defaultProvider == "anthropic");
    assert(config.defaultModel == "claude-sonnet-4");
    assert(!config.defaultThinking.isNull);
    assert(config.defaultThinking.get == 3);
    assert("myc" in config.abbreviations);
    assert(config.abbreviations["myc"] == "claude");
    assert("work" in config.aliases);
    assert(config.aliases["work"].runner.get == "oc");
    assert(config.aliases["work"].thinking.get == 1);
    assert(config.aliases["work"].agent.get == "reviewer");

    remove(tmpPath);
}

unittest {
    auto config = loadConfig("/nonexistent/path/config.toml");
    assert(config.defaultRunner == "oc");
}

unittest {
    auto parsed = parseArgs(["crush", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "crush");
    assert(r.argv[$ - 1] == "hello");
}

unittest {
    auto parsed = parseArgs(["kimi", "+1", "hello"]);
    auto config = defaultConfig();
    auto r = resolveCommand(parsed, config);
    assert(r.argv[0] == "kimi");
    assert(r.argv[1] == "--think");
    assert(r.argv[2] == "low");
}

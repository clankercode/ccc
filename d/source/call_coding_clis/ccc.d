module call_coding_clis.ccc;

import std.stdio;
import std.process;
import std.string : strip;

import call_coding_clis.runner : Runner, CommandSpec;
import call_coding_clis.parser : parseArgs, resolveCommand, CccConfig, ResolvedCommand;
import call_coding_clis.config : loadConfig;
import call_coding_clis.help : printHelp, printUsage;

int main(string[] args) {
    if (args.length < 2) {
        printUsage();
        return 1;
    }

    if (args.length == 2 && (args[1] == "--help" || args[1] == "-h")) {
        printHelp();
        return 0;
    }

    CccConfig config;
    auto configPath = environment.get("CCC_CONFIG");
    if (configPath !is null && configPath.length > 0) {
        config = loadConfig(configPath);
    }

    ResolvedCommand resolved;
    try {
        auto parsed = parseArgs(args[1 .. $]);
        resolved = resolveCommand(parsed, config);
    } catch (Exception e) {
        stderr.writeln(e.msg);
        return 1;
    }

    auto spec = CommandSpec(resolved.argv);
    foreach (k, v; resolved.env) {
        spec.env[k] = v;
    }

    auto realOpencode = environment.get("CCC_REAL_OPENCODE");
    if (realOpencode !is null) {
        spec.argv[0] = realOpencode;
    }

    auto runner = new Runner();
    auto result = runner.run(spec);

    if (result.stdout.length > 0) {
        write(result.stdout);
    }
    if (result.stderr.length > 0) {
        stderr.write(result.stderr);
    }
    return result.exit_code;
}

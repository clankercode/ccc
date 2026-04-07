module call_coding_clis.ccc;

import std.stdio;
import std.process;
import std.string : strip;

import call_coding_clis.runner : Runner, CommandSpec;
import call_coding_clis.prompt_spec : build_prompt_spec;

int main(string[] args) {
    if (args.length != 2) {
        stderr.writeln(`usage: ccc "<Prompt>"`);
        return 1;
    }

    CommandSpec spec;
    try {
        spec = build_prompt_spec(args[1]);
    } catch (Exception e) {
        stderr.writeln(e.msg);
        return 1;
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

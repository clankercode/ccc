module test_runner;

import std.stdio;
import std.exception;
import std.string : strip;

import call_coding_clis.runner : Runner, CommandSpec, CompletedRun;
import call_coding_clis.prompt_spec : build_prompt_spec;

unittest {
    auto spec = build_prompt_spec("hello");
    assert(spec.argv == ["opencode", "run", "hello"]);

    assertThrown!Exception(build_prompt_spec(""));
    assertThrown!Exception(build_prompt_spec("   "));

    auto trimmed = build_prompt_spec("  foo  ");
    assert(trimmed.argv == ["opencode", "run", "foo"]);

    assertThrown!Exception(build_prompt_spec(null));
}

unittest {
    auto runner = new Runner((CommandSpec s) {
        return CompletedRun(
            ["echo", "hello"],
            0,
            "hello\n",
            ""
        );
    });

    auto spec = build_prompt_spec("test");
    auto result = runner.run(spec);
    assert(result.exit_code == 0);
    assert(result.stdout == "hello\n");
    assert(result.stderr == "");
}

unittest {
    auto runner = new Runner();
    auto badSpec = CommandSpec(["/nonexistent_binary_xyz"]);
    auto result = runner.run(badSpec);
    assert(result.stderr.startsWith("failed to start /nonexistent_binary_xyz:"));
    assert(result.exit_code == 1);
}

unittest {
    auto runner = new Runner((CommandSpec s) {
        return CompletedRun(
            s.argv,
            0,
            "out",
            "err"
        );
    });

    string[][] events;
    auto spec = CommandSpec(["test"]);
    auto result = runner.stream(spec, (string kind, string data) {
        events ~= [kind, data];
    });

    assert(events.length == 2);
    assert(events[0] == ["stdout", "out"]);
    assert(events[1] == ["stderr", "err"]);
}

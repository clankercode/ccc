module call_coding_clis.runner;

import std.process;
import std.typecons : Nullable;
import std.string;
import std.array;

struct CommandSpec {
    string[] argv;
    Nullable!string stdin_text;
    Nullable!string cwd;
    string[string] env;
}

struct CompletedRun {
    string[] argv;
    int exit_code;
    string stdout;
    string stderr;
}

class Runner {
    CompletedRun delegate(CommandSpec) executor_;

    this() {
        executor_ = null;
    }

    this(CompletedRun delegate(CommandSpec) executor) {
        executor_ = executor;
    }

    CompletedRun run(CommandSpec spec) {
        if (executor_ !is null) {
            return executor_(spec);
        }
        return defaultRun(spec);
    }

    CompletedRun stream(CommandSpec spec, void delegate(string, string) on_event) {
        auto result = run(spec);
        if (result.stdout.length > 0) {
            on_event("stdout", result.stdout);
        }
        if (result.stderr.length > 0) {
            on_event("stderr", result.stderr);
        }
        return result;
    }

    static CompletedRun defaultRun(CommandSpec spec) {
        auto argv = spec.argv;
        auto argv0 = argv[0];

        try {
            auto env = std.process.environment.toAA();
            foreach (k, v; spec.env) {
                env[k] = v;
            }

            string workDir;
            if (!spec.cwd.isNull) {
                workDir = spec.cwd.get;
            }

            auto p = pipeProcess(argv, Redirect.all, env, Config.none, workDir.length > 0 ? workDir : null);
            p.stdin.write(spec.stdin_text.isNull ? "" : spec.stdin_text.get);
            p.stdin.close();

            auto outData = appender!string;
            foreach (chunk; p.stdout.byChunk(4096)) {
                outData.put(chunk);
            }
            auto errData = appender!string;
            foreach (chunk; p.stderr.byChunk(4096)) {
                errData.put(chunk);
            }

            auto status = wait(p.pid);

            return CompletedRun(
                argv,
                status,
                outData.data,
                errData.data
            );
        } catch (Exception e) {
            auto msg = e.msg.stripRight;
            return CompletedRun(
                argv,
                1,
                "",
                "failed to start " ~ argv0 ~ ": " ~ msg ~ "\n"
            );
        }
    }
}

# D Language Implementation Plan for call-coding-clis

## 1. Dub Package Structure

```
d/
├── dub.json              # package manifest
├── dub.sdl               # alternative: SDL format (choose one)
├── source/
│   └── callcodingclis/
│       ├── package.d         # public module re-exports
│       ├── command.d         # CommandSpec struct
│       ├── completed.d       # CompletedRun struct
│       ├── runner.d          # Runner, default executor
│       ├── prompt.d          # buildPromptSpec
│       └── app.d             # ccc CLI binary entry point
└── tests/
    └── test_all.d            # D unittest blocks + integration harness
```

### dub.json

```json
{
  "name": "call-coding-clis",
  "description": "Call coding CLIs from any language — D implementation",
  "license": "Unlicense",
  "targetType": "library",
  "configurations": [
    {
      "name": "library"
    },
    {
      "name": "ccc",
      "targetType": "executable",
      "mainSourceFile": "source/callcodingclis/app.d"
    }
  ],
  "dependencies": {},
  "buildRequirements": ["allowWarnings"]
}
```

Single `dub.json` with a `ccc` configuration for the binary. No external dependencies — everything is `std.process`, `std.stdio`, `std.string`, `std.array`, `std.algorithm`, `std.conv`, `std.range`, `std.traits`, `std.environment`, `std.typecons`.

---

## 2. Library API

### CommandSpec (`command.d`)

```d
struct CommandSpec {
    string[] argv;
    string   stdinText;
    string   cwd;
    string[string] env;

    this(string[] argv) pure nothrow @safe
    {
        this.argv = argv;
        this.stdinText = null;
        this.cwd = null;
        this.env = null;
    }

    CommandSpec withStdin(string text) return pure nothrow @safe
    {
        CommandSpec copy = this;
        copy.stdinText = text;
        return copy;
    }

    CommandSpec withCwd(string dir) return pure nothrow @safe
    {
        CommandSpec copy = this;
        copy.cwd = dir;
        return copy;
    }

    CommandSpec withEnv(string key, string value) return pure nothrow @safe
    {
        CommandSpec copy = this;
        copy.env[key] = value;
        return copy;
    }
}
```

Notes:
- `return` attribute enables NRVO on builder-pattern copies.
- Struct (value type), no GC heap needed for the spec itself.
- `string` is `immutable(char)[]` — zero-copy slices where possible.

### CompletedRun (`completed.d`)

```d
struct CompletedRun {
    string[] argv;
    int      exitCode;
    string   stdoutText;
    string   stderrText;
}
```

### Runner (`runner.d`)

```d
import std.process;
import std.stdio;

alias RunExecutor = CompletedRun function(ref CommandSpec) @system;
alias StreamCallback = void function(string stream, string data);
alias StreamExecutor = CompletedRun function(ref CommandSpec, StreamCallback) @system;

struct Runner {
    RunExecutor    runExec;
    StreamExecutor streamExec;

    this() nothrow @safe
    {
        this.runExec = &defaultRunExecutor;
        this.streamExec = &defaultStreamExecutor;
    }

    this(RunExecutor re, StreamExecutor se) nothrow @safe
    {
        this.runExec = re;
        this.streamExec = se;
    }

    CompletedRun run(ref CommandSpec spec) @system
    {
        return runExec(spec);
    }

    CompletedRun stream(ref CommandSpec spec, StreamCallback cb) @system
    {
        return streamExec(spec, cb);
    }
}
```

### buildPromptSpec (`prompt.d`)

```d
import std.string : strip;

CommandSpec buildPromptSpec(string prompt)
{
    auto trimmed = prompt.strip;
    if (trimmed.empty)
        throw new ValueError("prompt must not be empty");
    return CommandSpec(["opencode", "run", trimmed.idup]);
}
```

### Package barrel (`package.d`)

```d
module callcodingclis;
public import callcodingclis.command;
public import callcodingclis.completed;
public import callcodingclis.runner;
public import callcodingclis.prompt;
```

---

## 3. Subprocess via std.process

```d
import std.process;
import std.conv : text;

CompletedRun defaultRunExecutor(ref CommandSpec spec) @system
{
    auto env = spec.env.length
        ? environment.toAA ~ spec.env
        : null;

    auto result = spawnProcess(
        spec.argv,
        spec.cwd.length ? spec.cwd : null,
        env
    );

    auto output = result.output;  // PipeProcess or wait + collect
}
```

**Strategy: use `std.process.execute`** (Phobos) which returns `ProcessOutput` with `.output`, `.stderr`, `.status`:

```d
CompletedRun defaultRunExecutor(ref CommandSpec spec) @system
{
    try {
        auto config = ProcessConfig(
            spec.argv,
            spec.cwd.length ? spec.cwd : null,
            envForSpec(spec),
            spec.stdinText.length ? Redirect.pipe : Redirect.none
        );
        auto po = execute(config);
        return CompletedRun(
            spec.argv.idup,
            po.status,          // int
            cast(string) po.output,
            cast(string) po.stderr
        );
    } catch (ProcessException | Exception e) {
        string binary = spec.argv.length ? spec.argv[0] : "(unknown)";
        return CompletedRun(
            spec.argv.idup,
            1,
            null,
            "failed to start " ~ binary ~ ": " ~ e.msg ~ "\n"
        );
    }
}
```

**For `defaultStreamExecutor`:** D's `std.process` has limited streaming support. Match Rust's approach — delegate to `defaultRunExecutor` and call the callback with accumulated output, same as the Rust non-streaming `stream`:

```d
CompletedRun defaultStreamExecutor(ref CommandSpec spec, StreamCallback cb) @system
{
    auto result = defaultRunExecutor(spec);
    if (!result.stdoutText.empty)
        cb("stdout", result.stdoutText);
    if (!result.stderrText.empty)
        cb("stderr", result.stderrText);
    return result;
}
```

### Merged env helper

```d
string[string] envForSpec(ref CommandSpec spec) @system
{
    auto merged = environment.toAA;
    foreach (k, v; spec.env)
        merged[k] = v;
    return merged;
}
```

---

## 4. ccc CLI Binary (`app.d`)

```d
module callcodingclis.app;

import callcodingclis;
import std.stdio;
import std.process;
import std.string;
import core.stdc.stdlib : exit;

void main()
{
    auto args = environment.get("CCC_REAL_OPENCODE");
    // args not used here — it's for Runner level

    string[] positional = environment.args[1..$];
    if (positional.length != 1) {
        stderr.writeln(`usage: ccc "<Prompt>"`);
        exit(1);
    }

    CommandSpec spec;
    try {
        spec = buildPromptSpec(positional[0]);
    } catch (ValueError e) {
        stderr.writeln(e.msg);
        exit(1);
    }

    if (!spec.cwd.empty) spec.cwd = null;
    auto result = Runner().run(spec);
    if (!result.stdoutText.empty)
        stdout.write(result.stdoutText);
    if (!result.stderrText.empty)
        stderr.write(result.stderrText);

    exit(result.exitCode);
}
```

Exit code forwarding uses `core.stdc.stdlib.exit(result.exitCode)` to match the Rust/C behavior of forwarding the exact code (not just `return` from `main` which normalizes).

### CCC_REAL_OPENCODE support

Integrate into `buildPromptSpec` or into the CLI layer:

```d
string[] positional = environment.args[1..$];
// ...
CommandSpec spec;
try {
    spec = buildPromptSpec(positional[0]);
} catch (ValueError e) { ... }

auto override = environment.get("CCC_REAL_OPENCODE");
if (override !is null && !override.empty)
    spec.argv[0] = override;

auto result = Runner().run(spec);
```

This matches the C implementation's approach in `c/src/ccc.c:48-51`.

---

## 5. Prompt Trimming, Empty Rejection

Already covered in `buildPromptSpec` (Section 2):

1. `prompt.strip()` — removes leading/trailing whitespace (D's `std.string.strip` handles spaces, tabs, newlines, Unicode whitespace).
2. `trimmed.empty` — rejects empty or whitespace-only strings.
3. Throws `ValueError` with message `"prompt must not be empty"`.

Matches Python/Rust behavior exactly. The `.strip()` call in D handles Unicode by default, which is a minor improvement over C's `isspace()` approach but produces identical results for ASCII whitespace prompts.

---

## 6. Error Format: argv[0] Only

Per contract: `"failed to start <argv[0]>: <error>"`.

In `defaultRunExecutor`, the `catch` block:

```d
string binary = spec.argv.length ? spec.argv[0] : "(unknown)";
return CompletedRun(
    spec.argv.idup,
    1,
    null,
    "failed to start " ~ binary ~ ": " ~ e.msg ~ "\n"
);
```

Only `argv[0]` is used — never the full command string. This matches all other implementations.

---

## 7. Exit Code Forwarding

Two layers:

1. **Library layer** (`CompletedRun.exitCode`): stored as-is from the subprocess result.
2. **CLI layer**: uses `core.stdc.stdlib.exit(result.exitCode)` to forward the exact exit code, matching the Rust/C implementations. Using `return` from `main()` would also work in D but `exit()` guarantees the code is forwarded unmodified even in edge cases.

---

## 8. Test Strategy

### 8.1 D Unittest Blocks

Every module gets embedded `unittest` blocks:

```d
// In command.d
unittest {
    auto spec = CommandSpec(["echo", "hello"]);
    assert(spec.argv == ["echo", "hello"]);
    assert(spec.stdinText is null);
    assert(spec.cwd is null);
    assert(spec.env is null);

    auto s2 = spec.withStdin("data");
    assert(s2.stdinText == "data");
    assert(spec.stdinText is null);  // original unchanged
}

// In prompt.d
unittest {
    import std.exception : assertThrown;

    auto spec = buildPromptSpec("  hello world  ");
    assert(spec.argv == ["opencode", "run", "hello world"]);

    assertThrown!ValueError(buildPromptSpec(""));
    assertThrown!ValueError(buildPromptSpec("   \t\n  "));
}

// In runner.d — startup failure
unittest {
    CommandSpec spec = CommandSpec(["/nonexistent/binary/zzz"]);
    auto runner = Runner();
    auto result = runner.run(spec);
    assert(result.exitCode == 1);
    assert(result.stdoutText.empty);
    assert("failed to start" in result.stderrText);
}
```

Run all D unittests: `dub test`

### 8.2 CCC_REAL_OPENCODE Integration

- The D `ccc` binary respects `CCC_REAL_OPENCODE` env var (see Section 4).
- Add the D binary to `tests/test_ccc_contract.py` — add a new invocation alongside the existing Python/Rust/TypeScript/C blocks:

```python
# Build D binary first:
subprocess.run(["dub", "build", "--config=ccc", "-c", "release"], ...)

# Then test:
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "d/bin/ccc"), PROMPT],
        cwd=ROOT, env=env,
        capture_output=True, text=True, check=False,
    )
)
```

### 8.3 CI Integration

- `dub test` runs unittests.
- `python3 tests/test_ccc_contract.py` runs cross-language parity.
- CI matrix: add a D compiler (ldc2 or dmd) to the existing matrix.

---

## 9. D-Specific Design Decisions

### 9.1 Ranges and UFCS

Use D's range idiom throughout:

```d
// Environment merging via range operations
auto merged = environment.toAA
    .byPair
    .chain(spec.env.byPair)
    .assocArray!string;

// Empty check via .empty (range property)
if (result.stdoutText.empty) ...
```

Phobos algorithms (`strip`, `split`, `map`, `filter`) are preferred over C-style loops.

### 9.2 Templates

Minimize template complexity. The `Runner` uses function pointer aliases rather than templates for the executor injection, keeping the ABI simple:

```d
alias RunExecutor = CompletedRun function(ref CommandSpec) @system;
```

This avoids template bloat and makes the library interface stable. Use `return` attribute (NRVO) instead of template-based move semantics.

If future generic support is needed for executor injection (e.g., for mocking in tests), a simple template wrapper can be provided:

```d
CompletedRun run(S)(ref CommandSpec spec, S executor) @system
    if (is(S : RunExecutor))
{
    return executor(spec);
}
```

### 9.3 GC-Optional by Default

The library struct types (`CommandSpec`, `CompletedRun`, `Runner`) use only `string` (`immutable(char)[]`) which are fat pointers, not GC-allocated class instances. The actual string data from subprocess output *will* be GC-allocated (via Phobos internals), but:

- Library types are all structs (stack or static).
- No `new` for core types.
- `@nogc` is achievable for `buildPromptSpec` and `CommandSpec` builder methods.
- `@nogc` is NOT achievable for `Runner.run` due to `std.process` using GC internally — this is acceptable.

Mark what we can:

```d
struct CommandSpec {
    // All methods: pure nothrow @safe @nogc
}

struct CompletedRun {
    // Plain data: pure nothrow @safe @nogc by default
}
```

### 9.4 Scope Guards

Use `scope(exit)` and `scope(failure)` in the subprocess code:

```d
CompletedRun defaultRunExecutor(ref CommandSpec spec) @system
{
    auto proc = spawnProcess(spec.argv);
    scope(exit) {
        // Cleanup if needed — Phobos Process RAII handles most cases
    }
    // ...
}
```

In practice, `std.process.Process` is RAII-based and cleans up on scope exit, so explicit `scope` guards are less necessary than in C. They're useful in any manual resource management code (e.g., temporary file cleanup if needed).

### 9.5 @safe and @trusted

- **`CommandSpec`**, **`CompletedRun`**: fully `@safe` — no pointer manipulation, no system calls.
- **`buildPromptSpec`**: `@safe` (uses only `strip` and array ops).
- **`Runner.run`**: `@system` — delegates to `@system` executor that calls `std.process`.
- **`defaultRunExecutor`**: `@system` — subprocess spawning is inherently system-level.
- **`defaultStreamExecutor`**: `@system` — delegates to `@system` run executor.
- **`envForSpec`**: `@system` — reads `environment.toAA`.

Provide `@trusted` wrappers only if a safe API surface is needed:

```d
@system:
// Module-level annotation for runner.d since it's all subprocess code
```

---

## 10. Parity Gaps

### 10.1 Feature Parity Table (with D added)

| Feature              | Python | Rust | TypeScript | C      | D (planned) |
|----------------------|--------|------|------------|--------|-------------|
| build_prompt_spec    | yes    | yes  | yes        | yes    | yes         |
| Runner.run           | yes    | yes  | yes        | yes    | yes         |
| Runner.stream        | yes    | yes (non-streaming) | yes | no     | yes (non-streaming, matches Rust) |
| ccc CLI              | yes    | yes  | yes        | yes    | yes         |
| Prompt trimming      | yes    | yes  | yes        | yes    | yes         |
| Empty prompt rejection | yes  | yes  | yes        | yes    | yes         |
| Stdin/CWD/Env support | yes   | yes  | yes        | yes    | yes         |
| Startup failure reporting | yes | yes | yes      | yes    | yes         |
| Exit code forwarding | yes    | yes  | yes        | yes    | yes         |
| CCC_REAL_OPENCODE    | yes    | yes  | yes        | yes    | yes         |

### 10.2 Known Gaps vs. Other Implementations

1. **Non-streaming `stream`**: D will match Rust's approach — `stream()` calls the callback after the subprocess completes, rather than streaming output in real time. True streaming would require `std.process.PipeProcess` or manual `fork`/`pipe` like C. This matches Rust and is acceptable per the current contract.

2. **True streaming not implemented**: TypeScript and Python have real streaming via pipe-based I/O. D and Rust batch-output. If real streaming becomes contract, D can use `std.socket` or raw POSIX via `core.sys.posix.unistd`.

3. **No Makefile yet**: The C implementation has a `Makefile`; Rust uses Cargo. D will use `dub build --config=ccc`. A `Makefile` wrapper could be added for consistency but is not required.

4. **Unicode trimming**: D's `strip()` handles full Unicode whitespace, whereas C uses `isspace()` (locale-dependent, typically ASCII). This is a minor behavioral improvement and does not break contract.

### 10.3 Implementation Order

1. `d/dub.json` — package manifest
2. `source/callcodingclis/command.d` — CommandSpec
3. `source/callcodingclis/completed.d` — CompletedRun
4. `source/callcodingclis/prompt.d` — buildPromptSpec + unittests
5. `source/callcodingclis/runner.d` — Runner + default executors + unittests
6. `source/callcodingclis/package.d` — barrel re-exports
7. `source/callcodingclis/app.d` — ccc CLI binary
8. `dub test` — verify all unittests pass
9. Add D binary to `tests/test_ccc_contract.py` — cross-language parity verification

# D Language Implementation Plan for call-coding-clis

## 1. Build Instructions

### Prerequisites

- **D compiler**: dmd, ldc2, or gdc. Install via [DUB install guide](https://dlang.org/install.html).
- **dub**: bundled with dmd/ldc2. Verify with `dub --version`.

### Build

```sh
# Library only (default configuration)
dub build

# ccc CLI binary
dub build --config=ccc

# Release build (optimizations)
dub build --config=ccc --build=release

# Run all unittests
dub test

# Run a specific test
dub test --single source/callcodingclis/runner.d
```

### Clean

```sh
dub clean
```

### Cross-Language Contract Tests

```sh
# Build D binary, then run Python-based cross-language tests
dub build --config=ccc --build=release
python3 tests/test_ccc_contract.py
```

---

## 2. Dub Package Structure

```
d/
├── dub.json                    # package manifest (only this, no dub.sdl)
├── source/
│   └── callcodingclis/
│       ├── package.d           # public module re-exports
│       ├── command.d           # CommandSpec struct
│       ├── completed.d         # CompletedRun struct
│       ├── runner.d            # Runner, default executor
│       ├── prompt.d            # buildPromptSpec
│       └── app.d               # ccc CLI binary entry point
└── .gitignore                  # D build artifacts
```

### dub.json

```json
{
  "name": "call-coding-clis",
  "description": "Call coding CLIs from any language — D implementation",
  "license": "Unlicense",
  "targetType": "library",
  "targetPath": "bin",
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

Key decisions:
- **Single `dub.json`** — no `dub.sdl`. Pick one format; JSON is universal.
- `targetPath: "bin"` — output goes to `d/bin/` for predictable binary location.
- No external dependencies — everything uses `std.process`, `std.stdio`, `std.string`, `std.conv`, `std.algorithm`, `std.array`, `std.environment`, `std.range`, `std.traits`, `std.typecons`.

### d/.gitignore

```
bin/
.dub/
docs.json
docs/
```

---

## 3. Library API

### CommandSpec (`command.d`)

```d
struct CommandSpec {
    string[] argv;
    string   stdinText;
    string   cwd;
    string[string] env;

    this(string[] argv) pure nothrow @nogc @safe
    {
        this.argv = argv.idup;
        this.stdinText = null;
        this.cwd = null;
        // env left as init (null AA) — AAs default to null
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
- Constructor `@nogc`: no allocations except `.idup` on the argv array (stack-bound in practice for small arrays).

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

alias RunExecutor = CompletedRun function(ref CommandSpec) @system;
alias StreamCallback = void delegate(string stream, string data);
alias StreamExecutor = CompletedRun function(ref CommandSpec, StreamCallback) @system;

struct Runner {
    RunExecutor    runExec;
    StreamExecutor streamExec;

    this() nothrow @nogc @system
    {
        this.runExec = &defaultRunExecutor;
        this.streamExec = &defaultStreamExecutor;
    }

    this(RunExecutor re, StreamExecutor se) nothrow @nogc @system
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

Notes:
- `StreamCallback` is `delegate`, not `function` — allows closures (matches Rust/TypeScript patterns where callbacks capture context).
- The `Runner` constructor and methods are `@system` because they store and call `@system` function pointers. Do NOT mark them `@safe` — storing `@system` in `@safe` context is rejected by the compiler.

### buildPromptSpec (`prompt.d`)

```d
import std.string : strip;
import std.conv : ConvException;

CommandSpec buildPromptSpec(string prompt)
{
    auto trimmed = prompt.strip;
    if (trimmed.empty)
        throw new ConvException("prompt must not be empty");
    return CommandSpec(["opencode", "run", trimmed.idup]);
}
```

Notes:
- Throws `ConvException` (from `std.conv`) — a standard Phobos exception for conversion/validation failures. `ValueError` does not exist in Phobos.
- `.idup` on `trimmed` ensures the result is `immutable(char)[]` even if `strip` returned a mutable slice.

### Package barrel (`package.d`)

```d
module callcodingclis;
public import callcodingclis.command;
public import callcodingclis.completed;
public import callcodingclis.runner;
public import callcodingclis.prompt;
```

---

## 4. Subprocess via std.process

D's `std.process` provides two key functions:
- `execute` — runs a process, waits for completion, returns `ProcessOutput` (with `.output`, `.stderr`, `.status`). This is the correct function for the default run executor.
- `spawnProcess` — starts a process and returns a `Process` handle (for async/streaming use). NOT what we need here.

### defaultRunExecutor

```d
import std.process;
import std.conv : text;

CompletedRun defaultRunExecutor(ref CommandSpec spec) @system
{
    import std.exception : enforce;

    try {
        auto env = (spec.env.length > 0)
            ? envForSpec(spec)
            : null;

        auto po = execute(
            spec.argv,
            (spec.cwd.length > 0) ? spec.cwd : null,
            env,
            Config.none,
            (spec.stdinText.length > 0) ? Redirect.pipe : Redirect.none
        );

        return CompletedRun(
            spec.argv.idup,
            po.status,
            cast(string) po.output,
            cast(string) po.stderr
        );
    } catch (ProcessException | Exception e) {
        string binary = spec.argv.length > 0 ? spec.argv[0] : "(unknown)";
        return CompletedRun(
            spec.argv.idup,
            1,
            null,
            "failed to start " ~ binary ~ ": " ~ e.msg ~ "\n"
        );
    }
}
```

Notes on the `execute` call signature (Phobos):
```d
ProcessOutput execute(
    string[] args,
    string workDir = null,
    string[string] env = null,
    Config config = Config.none,
    Redirect stdin = Redirect.none
);
```
- `spec.cwd.length > 0` — D's AA `.length` returns 0 for `null`. For `string`, `.length > 0` correctly distinguishes non-null from empty. Use `!spec.cwd.empty` equivalently (`.empty` returns `true` for both `null` and `""`).
- Do NOT use `ProcessConfig` — that struct is for `spawnProcess`, not `execute`.

### defaultStreamExecutor

D's `std.process` has limited true streaming support. Match Rust's approach — delegate to `defaultRunExecutor` and call the callback with accumulated output:

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

This matches Rust's non-streaming `stream` implementation exactly.

### envForSpec helper

```d
import std.environment : environment;

string[string] envForSpec(ref CommandSpec spec) @system
{
    auto merged = environment.toAA();
    foreach (k, v; spec.env)
        merged[k] = v;
    return merged;
}
```

Note: Call with `spec.env.length > 0` guard to avoid the overhead of copying the full environment when no overrides are needed.

---

## 5. ccc CLI Binary (`app.d`)

```d
module callcodingclis.app;

import callcodingclis;
import std.stdio;
import std.process : environment;
import core.stdc.stdlib : exit;

void main()
{
    string[] positional = environment.args[1..$];
    if (positional.length != 1) {
        stderr.writeln(`usage: ccc "<Prompt>"`);
        exit(1);
    }

    CommandSpec spec;
    try {
        spec = buildPromptSpec(positional[0]);
    } catch (ConvException e) {
        stderr.writeln(e.msg);
        exit(1);
    }

    auto override = environment.get("CCC_REAL_OPENCODE");
    if (override !is null && !override.empty)
        spec.argv[0] = override;

    auto result = Runner().run(spec);
    if (!result.stdoutText.empty)
        stdout.write(result.stdoutText);
    if (!result.stderrText.empty)
        stderr.write(result.stderrText);

    exit(result.exitCode);
}
```

Notes:
- `core.stdc.stdlib.exit(result.exitCode)` forwards the exact exit code, matching Rust (`std::process::exit`) and C (`return exit_code` from `main`). Using `return result.exitCode` from `main()` in D would also work but `exit()` is explicit.
- `CCC_REAL_OPENCODE` overrides `argv[0]` (the binary name) in the spec, matching the C implementation at `c/src/ccc.c:48-51`.
- `ConvException` catch matches the exception thrown by `buildPromptSpec`.
- `environment.args` — correct Phobos API for `main` args (equivalent to C's `argc/argv`).

---

## 6. Error Format: argv[0] Only

Per contract: `"failed to start <argv[0]>: <error>"`.

In `defaultRunExecutor`, the catch block uses only `argv[0]`:

```d
string binary = spec.argv.length > 0 ? spec.argv[0] : "(unknown)";
return CompletedRun(
    spec.argv.idup,
    1,
    null,
    "failed to start " ~ binary ~ ": " ~ e.msg ~ "\n"
);
```

This matches all other implementations.

---

## 7. Exit Code Forwarding

Two layers:

1. **Library layer** (`CompletedRun.exitCode`): stored as-is from `ProcessOutput.status` (which is the raw exit code from `waitpid`).
2. **CLI layer**: `core.stdc.stdlib.exit(result.exitCode)` forwards the exact exit code unmodified.

Note: `ProcessOutput.status` in Phobos returns the raw exit status (not shifted). On POSIX, `waitpid` returns status in the high bits; Phobos `execute` already extracts the actual exit code via `WEXITSTATUS`. This is transparent and correct.

---

## 8. Prompt Trimming, Empty Rejection

Covered in `buildPromptSpec` (Section 3):

1. `prompt.strip()` — removes leading/trailing whitespace. D's `std.string.strip` handles ASCII whitespace by default (same as C's `isspace`).
2. `trimmed.empty` — rejects empty or whitespace-only strings.
3. Throws `ConvException` with message `"prompt must not be empty"`.

Matches Python/Rust/C behavior. The error message string must be identical across implementations for cross-language test consistency.

---

## 9. Test Strategy

### 9.1 D Unittest Blocks

Every module gets embedded `unittest` blocks. These run via `dub test`.

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

    auto s3 = spec.withCwd("/tmp");
    assert(s3.cwd == "/tmp");
    assert(spec.cwd is null);

    auto s4 = spec.withEnv("KEY", "val");
    assert(s4.env["KEY"] == "val");
    assert(spec.env is null);
}

// In prompt.d
unittest {
    import std.exception : assertThrown;

    auto spec = buildPromptSpec("  hello world  ");
    assert(spec.argv == ["opencode", "run", "hello world"]);

    assertThrown!ConvException(buildPromptSpec(""));
    assertThrown!ConvException(buildPromptSpec("   \t\n  "));
}

// In runner.d — startup failure
unittest {
    CommandSpec spec = CommandSpec(["/nonexistent/binary/zzz"]);
    auto runner = Runner();
    auto result = runner.run(spec);
    assert(result.exitCode == 1);
    assert(result.stdoutText.empty || result.stdoutText is null);
    assert(result.stderrText !is null);
    assert("failed to start" in result.stderrText);
}

// In runner.d — echo smoke test
unittest {
    CommandSpec spec = CommandSpec(["echo", "hello"]);
    auto runner = Runner();
    auto result = runner.run(spec);
    assert(result.exitCode == 0);
    assert("hello" in result.stdoutText);
}
```

### 9.2 Cross-Language Test Registration

Add the D binary to `tests/test_ccc_contract.py` in each of the four test methods (`test_cross_language_ccc_happy_path`, `test_cross_language_ccc_rejects_empty_prompt`, `test_cross_language_ccc_requires_one_prompt_argument`, `test_cross_language_ccc_rejects_whitespace_only_prompt`). After the C block in each method, add:

```python
# D
subprocess.run(
    ["dub", "build", "--config=ccc", "--build=release"],
    cwd=ROOT / "d",
    env=env,
    capture_output=True,
    text=True,
    check=True,
)
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "d" / "bin" / "ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

For the empty/whitespace/missing tests, replace `self.assert_equal_output` with `self.assert_rejects_empty` or `self.assert_rejects_missing_prompt` respectively, matching the existing pattern.

The D binary path is `d/bin/ccc` (set by `targetPath` in `dub.json`).

### 9.3 Running Tests

```sh
# D-only unittests
dub test

# Full cross-language parity
dub build --config=ccc --build=release
python3 tests/test_ccc_contract.py
```

---

## 10. CI Notes

### GitHub Actions

Add a D job to the existing CI matrix:

```yaml
jobs:
  d-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dc: [dmd, ldc]
    steps:
      - uses: actions/checkout@v4
      - uses: dlang-community/setup-dlang@v2
        with:
          compiler: ${{ matrix.dc }}
      - name: Build ccc binary
        run: dub build --config=ccc --build=release
        working-directory: d
      - name: Run D unittests
        run: dub test
        working-directory: d
      - name: Cross-language contract tests
        run: python3 tests/test_ccc_contract.py
```

Notes:
- `dlang-community/setup-dlang@v2` is the standard GitHub Action for D compilers.
- Test both `dmd` (reference compiler, fast builds) and `ldc` (LLVM-based, better optimizations).
- The cross-language contract tests require `dub` and the D compiler to be on PATH (provided by setup-dlang).
- The D build must complete before contract tests can find `d/bin/ccc`.

---

## 11. D-Specific Design Decisions

### 11.1 Ranges and UFCS

Use D's range idiom throughout:

```d
// Empty check via .empty (range property)
if (result.stdoutText.empty) ...

// Phobos algorithms preferred over C-style loops
auto trimmed = prompt.strip;
```

### 11.2 Function Pointers, Not Templates

The `Runner` uses function pointer aliases rather than templates for executor injection:

```d
alias RunExecutor = CompletedRun function(ref CommandSpec) @system;
```

This avoids template bloat and keeps the ABI simple and stable. If mocking in tests requires closures, use the constructor that accepts custom `RunExecutor`/`StreamExecutor` pointers pointing to module-level `@system` wrapper functions.

### 11.3 GC-Optional by Default

Library struct types (`CommandSpec`, `CompletedRun`, `Runner`) use only `string` (`immutable(char)[]`) which are fat pointers. The actual string data from subprocess output is GC-allocated via Phobos internals, but:

- Library types are all structs (stack or static).
- No `new` for core types.
- `@nogc` is achievable for `CommandSpec` builder methods.
- `@nogc` is NOT achievable for `Runner.run` due to `std.process` using GC internally — this is acceptable and matches all other D subprocess libraries.

### 11.4 @safe, @system, @trusted

- **`CommandSpec`**, **`CompletedRun`**: fully `@safe` — no pointer manipulation, no system calls.
- **`buildPromptSpec`**: `@safe` (uses only `strip` and array ops).
- **`Runner`**: `@system` — stores and calls `@system` function pointers.
- **`defaultRunExecutor`**: `@system` — subprocess spawning is inherently system-level.
- **`defaultStreamExecutor`**: `@system` — delegates to `@system` run executor.
- **`envForSpec`**: `@system` — reads `environment.toAA()`.

Module-level `@system:` annotation in `runner.d` since the entire module is subprocess code:

```d
@system:
module callcodingclis.runner;
```

### 11.5 Scope Guards

Use `scope(exit)` and `scope(failure)` if manual resource management is needed. In practice, `std.process.Process` is RAII-based and cleans up on scope exit. No explicit scope guards needed for the default executor.

---

## 12. Parity Gaps

### 12.1 Feature Parity Table

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

### 12.2 Known Gaps vs. Other Implementations

1. **Non-streaming `stream`**: D matches Rust's approach — `stream()` calls the callback after subprocess completion, not during. If real streaming becomes contract, D can use `std.socket` or raw POSIX via `core.sys.posix.unistd`.

2. **No Makefile**: C has a `Makefile`; Rust uses Cargo. D uses `dub build --config=ccc`. A Makefile wrapper could be added for consistency but is not required by the contract.

3. **Unicode trimming**: D's `std.string.strip` handles Unicode whitespace by default. C's `isspace()` is locale-dependent (typically ASCII). This is a minor behavioral improvement and does not break the contract.

---

## 13. Implementation Order

1. `d/dub.json` — package manifest
2. `d/.gitignore` — build artifacts
3. `source/callcodingclis/command.d` — CommandSpec + unittests
4. `source/callcodingclis/completed.d` — CompletedRun
5. `source/callcodingclis/prompt.d` — buildPromptSpec + unittests
6. `source/callcodingclis/runner.d` — Runner + default executors + envForSpec + unittests
7. `source/callcodingclis/package.d` — barrel re-exports
8. `source/callcodingclis/app.d` — ccc CLI binary
9. `dub test` — verify all D unittests pass
10. `dub build --config=ccc --build=release` — verify binary builds
11. Manual smoke test: `d/bin/ccc "hello world"`
12. Add D blocks to `tests/test_ccc_contract.py` — all four test methods
13. `python3 tests/test_ccc_contract.py` — verify cross-language parity

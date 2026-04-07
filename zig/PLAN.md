# Zig Implementation Plan

## 1. Project Structure

```
zig/
  build.zig              # build definition: library + ccc exe + test step
  build.zig.zon          # project manifest (name, version, minimum Zig version)
  Makefile               # thin wrapper for contract-test integration
  src/
    lib.zig              # public API: types, build_prompt_spec, Runner
    runner.zig           # Runner implementation (std.process.Child)
    prompt.zig           # build_prompt_spec + trim logic
    ccc.zig              # CLI entry point (main)
```

`build.zig` exposes two installable artifacts:
- `lib` — a static library exposing the public API
- `ccc` — the CLI binary

The test step runs via `zig build test` (invoked from `Makefile test` for consistency with `c/Makefile`).

## 2. Build Instructions

### Prerequisites

- Zig 0.13.0 or later (the `std.Build` API stabilized in 0.13).  Pin `minimum_zig_version` in `build.zig.zon` accordingly.

### Build the `ccc` binary

```sh
cd zig
zig build install --prefix dist
# produces dist/bin/ccc
```

Or via the Makefile (used by the cross-language contract tests):

```sh
make -C zig build/ccc
# produces zig/build/ccc  (matches c/build/ccc layout)
```

### Run unit tests

```sh
cd zig
zig build test
```

### Clean

```sh
cd zig
make clean
# or: rm -rf zig-out zig-cache .zig-cache
```

## 3. Makefile

A minimal Makefile matching the `c/Makefile` pattern so the contract tests can discover the binary at a predictable path:

```makefile
build/ccc:
	mkdir -p build
	zig build-exe src/ccc.zig -femit-bin=build/ccc --name ccc

clean:
	rm -rf build zig-out zig-cache .zig-cache

test: build/ccc
	zig build test
```

Note: `zig build-exe` is used instead of `zig build` for the bare binary to avoid pulling in the library artifact and keep the Makefile target self-contained. The `-femit-bin` flag places the output at `build/ccc` matching the convention expected by `tests/test_ccc_contract.py`.

## 4. Library API

### CommandSpec

```zig
pub const CommandSpec = struct {
    argv: [][]const u8,
    stdin_text: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    env: std.StringHashMap([]const u8),
};
```

- `argv` is owned by the caller. The library does not copy/free it.
- `env` maps are added *on top of* the current process environment (not a full replacement). `std.process.Child` accepts `env_map` which replaces the environment entirely — so the runner **must** clone `std.os.environMap()` and merge the caller's overrides into it before passing it to `Child.spawn`.

### CompletedRun

```zig
pub const CompletedRun = struct {
    argv: [][]const u8,
    exit_code: u8,
    stdout: []u8,       // allocator-owned, caller must free via deinit
    stderr: []u8,       // allocator-owned, caller must free via deinit

    pub fn deinit(self: *CompletedRun, allocator: std.mem.Allocator) void;
};
```

- `exit_code` is `u8` (Unix exit codes are 0–255). Signal exits are mapped to 1 (matching Rust's `unwrap_or(1)` pattern).
- `argv` is a shallow copy; only `stdout` and `stderr` need deallocation.
- On spawn failure: `exit_code = 1`, `stderr` contains the `"failed to start ..."` message, `stdout` is an empty slice. These `stderr` bytes are allocator-owned and freed by `deinit`.

### Runner

```zig
pub const Runner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Runner;
    pub fn deinit(self: *Runner) void;

    pub fn run(self: *Runner, spec: CommandSpec) error{OutOfMemory}CompletedRun;
};
```

**Critical design decision:** `run` returns `error{OutOfMemory}CompletedRun`, **not** a bare `CompletedRun`. This differs from the Rust/Python pattern where all errors are in-band. In Zig, only OOM propagates as an error — spawn failures are caught internally and encoded as `exit_code: 1` + stderr message in the `CompletedRun`. The error union is narrow so callers who cannot handle OOM can still propagate it easily.

No `stream` in v1 — matches the C implementation. Zig's `std.process.Child` supports `stdin`, `stdout`, `stderr` as `ProcessIo`. We pipe all three and collect output after `wait()`. If/when streaming is needed later, the `Child` API exposes file descriptors that can be polled.

### build_prompt_spec

```zig
pub fn build_prompt_spec(allocator: std.mem.Allocator, prompt: []const u8) BuildPromptSpecError!CommandSpec;

const BuildPromptSpecError = error{EmptyPrompt} || std.mem.Allocator.Error;
```

- Trims leading/trailing whitespace from `prompt`.
- Returns `error.EmptyPrompt` if the trimmed result is empty.
- Allocates `argv = &.{"opencode", "run", trimmed_prompt}` — the trimmed copy is allocator-owned.
- The returned `CommandSpec.env` is initialized as an empty `std.StringHashMap` (caller populates if needed).

## 5. Subprocess via std.process.Child

Key points from Zig's `std.process.Child`:

- `Child.spawn()` returns `Child` with `stdin`, `stdout`, `stderr` as optional `File`.
- Use `.{ .stdin = .pipe, .stdout = .pipe, .stderr = .pipe }` in `ProcessIo.Options`.
- After spawning, `child.wait()` returns `std.process.Child.Term` (`.Exited` with u8 code, `.Signal`, `.Stopped`, or `.Unknown`).
- Read stdout/stderr to completion **before** `wait()` to avoid pipe deadlock. Since child processes here produce bounded output (not streaming megabytes interactively), sequential reads after closing stdin are acceptable for v1.
- On `child.wait()` return: map `.Exited(code)` → `code`, `.Signal`, `.Stopped`, `.Unknown` → `1`.

### Startup failure handling

`Child.spawn()` returns an error (e.g., `error.FileNotFound`, `error.AccessDenied`). Catch these and produce a `CompletedRun` with:

```zig
CompletedRun{
    .argv = spec.argv,
    .exit_code = 1,
    .stdout = "",
    .stderr = try std.fmt.allocPrint(allocator, "failed to start {s}: {s}\n", .{
        spec.argv[0],
        @errorName(err),
    }),
}
```

This matches the C implementation's `dprintf(STDERR_FILENO, "failed to start %s: %s\n", ...)` and the Rust/Python error format exactly.

### Environment merge

`std.process.Child` with `env_map` set replaces the entire environment. To match the Python/Rust/TS behavior of adding overrides on top of the current process env:

```zig
const env_map = try std.process.getEnvMap(allocator);
var it = spec.env.iterator();
while (it.next()) |entry| {
    try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
}
child_process.env_map = &env_map;
```

### Stdin piping

If `spec.stdin_text != null`:
1. Set `.stdin = .pipe` in `ProcessIo`.
2. After spawn, `child.stdin` is a `std.process.Child.Stdio` — write `spec.stdin_text`, then `child.stdin.close()`.

If `spec.stdin_text == null`:
1. Set `.stdin = .ignore` (child reads EOF immediately, matching Rust's behavior of not providing stdin when not needed).

### CWD handling

Pass `spec.cwd` through to `Child.spawn`'s `cwd` parameter. If null, the child inherits the parent's working directory.

### Pipe deadlock avoidance

Read stdout and stderr sequentially: read all of stdout first, then all of stderr (or vice versa). Since child processes here produce bounded output, sequential reads after closing stdin are acceptable for v1. If the child produces large output on both pipes simultaneously, switch to `std.Thread`-based parallel reads in a future version.

## 6. ccc CLI Binary

`src/ccc.zig` contains `pub fn main() !void`:

1. Parse `std.process.args()` — skip program name, require exactly 1 remaining arg.
2. If arg count != 1: write `"usage: ccc \"<Prompt>\"\n"` to stderr, return `std.process.exit(1)`.
3. Call `build_prompt_spec(gpa, arg[0])` — on `error.EmptyPrompt`, write `"prompt must not be empty\n"` to stderr, return `std.process.exit(1)`.
4. Resolve binary: read env `CCC_REAL_OPENCODE`; fall back to `"opencode"`. Replace `argv[0]` in the spec. Note: since `build_prompt_spec` allocates the argv slice and `"opencode"` is the first element, the CLI must dup the resolved binary name and patch `argv[0]` in the allocated slice.
5. Create a `Runner`, call `runner.run(spec)`. On OOM, print error to stderr and exit 1.
6. If `result.stdout.len > 0`, write it to stdout.
7. If `result.stderr.len > 0`, write it to stderr.
8. Extract exit code, then call `result.deinit(gpa)` and `runner.deinit()`, then `std.process.exit(exit_code)`.

### std.process.exit and deferred cleanup

`std.process.exit()` bypasses deferred destructors. To avoid leaking:

```zig
const exit_code = result.exit_code;
result.deinit(gpa);
runner.deinit();
std.process.exit(exit_code);
```

This matches Rust's `ccc.rs` which calls `std::process::exit(result.exit_code)` and differs from the C implementation which returns the exit code from `main()` (also fine — Zig's `main` returning `!void` requires explicit exit).

## 7. Prompt Trimming and Empty Rejection

`src/prompt.zig`:

- `trim(prompt: []const u8) []const u8` — returns a subslice with leading/trailing whitespace removed. Pure byte-level, no allocation (Zig `std.mem.trim` operates on slices, returns subslice of input).
- `build_prompt_spec` calls `std.mem.trim(u8, prompt, " \t\n\r")`, checks length, allocates the trimmed copy, builds the `CommandSpec`.
- Error: `error.EmptyPrompt`.

## 8. Error Format

On subprocess spawn failure:

```
failed to start <argv[0]>: <error_name>
```

- `argv[0]` only, not the full command line.
- Example: `failed to start nonexistent_binary: FileNotFound\n`
- Uses `@errorName(err)` which returns the Zig error name string (e.g., `"FileNotFound"`, `"AccessDenied"`).
- **Whitespace difference note:** Zig's `@errorName` returns no spaces (e.g., `FileNotFound`), while C's `strerror(errno)` returns `No such file or directory`. The contract tests only check that stderr *contains* `"failed to start"`, so this is acceptable. However, for exactness across implementations, we could use `std.os.errno` mapping to get OS-level descriptions — but `@errorName` is simpler and sufficient. If exact parity is later required, use `std.posix.errnoToEmoji` or format the OS error string via `std.os.strerror`.

## 9. Exit Code Forwarding

The `ccc` binary forwards the child's exit code via `std.process.exit()`:

```zig
const exit_code = result.exit_code;
result.deinit(gpa);
runner.deinit();
std.process.exit(exit_code);
```

Signal exits → exit code 1 (consistent with all other implementations).

## 10. Test Strategy

### Built-in Zig tests

Each source file contains a `test` block at the bottom:

```zig
test "build_prompt_spec trims and builds argv" { ... }
test "build_prompt_spec rejects empty prompt" { ... }
test "build_prompt_spec rejects whitespace-only prompt" { ... }
test "Runner.run captures stdout and stderr" { ... }
test "Runner.run returns exit code from child" { ... }
test "Runner.run reports startup failure for nonexistent binary" { ... }
```

Run via `zig build test` (or `make -C zig test`).

### Test helpers for subprocess tests

For tests that spawn real subprocesses, create small test binaries using `zig build-exe` at comptime, or shell out to system commands (`true`, `false`, `echo`). For example:

```zig
test "Runner.run captures stdout" {
    const spec = CommandSpec{
        .argv = &[_][]const u8{ "/bin/echo", "hello" },
        .env = std.StringHashMap([]const u8).init(allocator),
    };
    var runner = Runner.init(allocator);
    defer runner.deinit();
    const result = try runner.run(spec);
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings("hello\n", result.stdout);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
```

### CCC_REAL_OPENCODE override

The library does not read `CCC_REAL_OPENCODE` — it uses whatever `argv[0]` is given. The CLI binary reads it and patches `argv[0]` before calling the runner, matching the C implementation. In tests, set it explicitly or pass the desired binary path as `argv[0]`.

## 11. Cross-Language Contract Test Registration

Add a Zig block to each test method in `tests/test_ccc_contract.py`. The pattern follows the C implementation:

```python
# In each test method, after the C block:

subprocess.run(
    ["make", "-C", "zig", "build/ccc"],
    cwd=ROOT,
    env=env,
    capture_output=True,
    text=True,
    check=True,
)
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "zig/build/ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Same pattern for `assert_rejects_empty`, `assert_rejects_missing_prompt`, and the whitespace-only prompt test.

### Changes to tests/test_ccc_contract.py

Add the Zig block to all four test methods:
1. `test_cross_language_ccc_happy_path`
2. `test_cross_language_ccc_rejects_empty_prompt`
3. `test_cross_language_ccc_requires_one_prompt_argument`
4. `test_cross_language_ccc_rejects_whitespace_only_prompt`

### Prerequisite

The test runner must have `zig` on `PATH`. If `zig` is not available, the Zig block should be skipped — wrap with `unittest.skipUnless(shutil.which("zig"), "zig not available")` at the class or method level.

## 12. CI Notes

### Zig availability

Zig is not universally available in CI runners. Add a CI step to install it:

```yaml
- name: Install Zig
  run: |
    curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ
    echo "$PWD/zig-linux-x86_64-0.13.0" >> $GITHUB_PATH
```

### Test matrix

Zig tests run only on Linux (matching existing convention — no Windows/macOS CI for other implementations either). Add a CI job:

```yaml
zig-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Install Zig
      run: <install-snippet>
    - name: Build
      run: make -C zig build/ccc
    - name: Unit tests
      run: make -C zig test
    - name: Contract tests
      run: python3 -m pytest tests/test_ccc_contract.py -k "cross_language"
```

### No CI workflow file exists yet

There is no `.github/workflows/` directory in the repository. When CI is added, include the Zig job alongside C/Rust/TS/Python jobs. Until then, manual testing via `make -C zig test` and `python3 -m pytest tests/test_ccc_contract.py` is sufficient.

## 13. Zig-Specific Considerations

### Comptime

- The error set for `build_prompt_spec` is comptime-known: `BuildPromptSpecError = error{EmptyPrompt} || std.mem.Allocator.Error`.
- No runtime type introspection. All types are structs with known layouts.
- `std.mem.trim` is a comptime-safe slice operation.

### Allocators

- The library API takes an `allocator` parameter (no global allocator).
- The CLI binary uses `std.heap.GeneralPurposeAllocator` for its own allocations.
- `CommandSpec` fields that are borrowed (`argv` items, optional `cwd`, `stdin_text`) are `[]const u8` slices — the caller retains ownership.
- `CompletedRun.stdout` and `CompletedRun.stderr` are allocator-owned `[]u8` slices freed via `deinit()`.
- `CommandSpec.env` is owned by whoever creates the `HashMap`. The library reads it but does not take ownership.

### Error Unions

- `build_prompt_spec` returns `BuildPromptSpecError!CommandSpec`.
- `Runner.run` returns `error{OutOfMemory}CompletedRun` — only OOM propagates. All subprocess errors are in-band (exit_code + stderr).
- The CLI catches OOM with a simple stderr message + exit 1.

### No Hidden Control Flow

- No exceptions, no panics in library code.
- `std.process.exit()` is called exactly once, in the CLI main, with explicit intent.
- No `defer` trickery that could mask errors — cleanup is explicit before `exit()`.

### Slices vs. Owned Strings

- Zig uses `[]const u8` for string-like data. No implicit copies.
- `std.mem.trim` returns a subslice (no allocation). The trimmed result is copied only when building the `CommandSpec` argv.

### build.zig.zon minimum version

Pin to `0.13.0`. The `std.Build` API and `std.process.Child` are stable at this version.

## 14. Parity Checklist

| Concern | Status | Notes |
|---------|--------|-------|
| `build_prompt_spec` | Planned | Trims, rejects empty, returns `CommandSpec` with `argv = {"opencode","run","<trimmed>"}` |
| `Runner.run` | Planned | Spawns child, collects stdout/stderr, returns `CompletedRun` |
| `Runner.stream` | Not in v1 | Matches C. Add later using fd polling or `std.Thread`. |
| `ccc` CLI | Planned | Parses args, calls `build_prompt_spec`, runs, forwards output + exit code |
| Prompt trimming | Planned | `std.mem.trim(u8, prompt, " \t\n\r")` |
| Empty prompt rejection | Planned | `error.EmptyPrompt` → stderr `"prompt must not be empty\n"`, exit 1 |
| Missing/extra args | Planned | stderr `"usage: ccc \"<Prompt>\"\n"`, exit 1 |
| Stdin piping | Planned | `.stdin = .pipe` if `stdin_text != null`, `.stdin = .ignore` otherwise |
| CWD handling | Planned | Pass `spec.cwd` to `Child.spawn` |
| Env merge semantics | Planned | Clone `getEnvMap`, merge `spec.env` overrides, pass to child |
| Startup failure reporting | Planned | `"failed to start <argv[0]>: <error_name>\n"`, exit code 1 |
| Exit code forwarding | Planned | `std.process.exit(result.exit_code)` in CLI |
| Signal exit mapping | Planned | `Term.Signal`/`Term.Stopped`/`Term.Unknown` → exit code 1 |
| `CCC_REAL_OPENCODE` | Planned | CLI reads env, patches `argv[0]`. Not in library. |
| Cross-language tests | Planned | Add Zig blocks to all 4 contract test methods |
| Non-POSIX support | Not in v1 | Zig supports Windows, but test matrix is POSIX-only per convention |
| `build.zig.zon` min version | Planned | Pin to 0.13.0 |

## 15. Self-Contained Implementation

This plan is fully implementable without reading any other language's plan or implementation. All required behavior is specified inline:

- The `CommandSpec`, `CompletedRun`, and `Runner` types are fully defined.
- The `ccc` CLI behavior is fully specified (arg parsing, error messages, exit codes).
- The subprocess spawning strategy is documented with Zig stdlib APIs.
- Test cases are enumerated with expected assertions.
- Cross-language test registration is specified with exact code snippets.
- Build instructions cover both `zig build` and Makefile paths.

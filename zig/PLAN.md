# Zig Implementation Plan

## 1. Project Structure

```
zig/
  build.zig              # build definition: library + ccc exe + step for tests
  build.zig.zon          # project manifest (name, version, dependencies)
  src/
    lib.zig              # public API: types, build_prompt_spec, Runner
    runner.zig           # Runner implementation (std.process.Child)
    prompt.zig           # build_prompt_spec + trim logic
    ccc.zig              # CLI entry point (main)
```

`build.zig` exposes two installable artifacts:
- `lib` — a static library exposing the public API
- `ccc` — the CLI binary

The test step runs `zig build test`.

## 2. Library API

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
- `env` maps are added *on top of* the current process environment (not a full replacement).

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

### Runner

```zig
pub const Runner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Runner;
    pub fn deinit(self: *Runner) void;

    pub fn run(self: *Runner, spec: CommandSpec) !CompletedRun;
};
```

No `stream` in v1 — matches the C implementation. Zig's `std.process.Child` supports `stdin`, `stdout`, `stderr` as `ProcessIo`. We pipe all three and collect output after `wait()`. If/when streaming is needed later, the `Child` API exposes file descriptors that can be polled.

### build_prompt_spec

```zig
pub fn build_prompt_spec(allocator: std.mem.Allocator, prompt: []const u8) !CommandSpec;
```

- Trims leading/trailing whitespace from `prompt`.
- Returns `error.EmptyPrompt` if the trimmed result is empty.
- Allocates `argv = &.{"opencode", "run", trimmed_prompt}` — the trimmed copy is allocator-owned.

## 3. Subprocess via std.process.Child

Key points from Zig's `std.process.Child`:

- `Child.spawn()` returns `Child` with `stdin`, `stdout`, `stderr` as optional `File`.
- Use `.{ .stdin = .pipe, .stdout = .pipe, .stderr = .pipe }` in `ProcessIo.Options`.
- After spawning, `child.wait()` returns `std.process.Child.Term` (`.Exited` with u8 code, `.Signal`, `.Stopped`, or `.Unknown`).
- Read stdout/stderr to completion before or after `wait()` (Zig recommends before to avoid pipe deadlock — use `std.io.getStdErr()` pattern or read in parallel; simplest: use `collectOutput` by reading stdout then stderr sequentially after closing stdin).
- Startup failure: `Child.spawn()` returns an error union. On `error.FileNotFound` or similar, construct stderr string `"failed to start {argv[0]}: {error_text}\n"` and return a `CompletedRun` with `exit_code = 1`.

### Pipe deadlock avoidance

Read stdout and stderr sequentially. Since child processes here are expected to produce bounded output (they're not streaming megabytes interactively), sequential reads after closing stdin and waiting are acceptable for v1. If the child produces large output on both pipes, we can switch to `std.Thread` or `std.process.Child.spawn` with `std.io.poll` later.

## 4. ccc CLI Binary

`src/ccc.zig` contains `pub fn main() !u8`:

1. Parse `std.process.args()` — skip program name, require exactly 1 remaining arg.
2. If arg count != 1: write `"usage: ccc \"<Prompt>\"\n"` to stderr, return exit code 1.
3. Call `build_prompt_spec(gpa, arg[0])` — on `error.EmptyPrompt`, write `"prompt must not be empty\n"` to stderr, return 1.
4. Resolve binary: read env `CCC_REAL_OPENCODE`; fall back to `"opencode"`. Replace `argv[0]` in the spec.
5. Create a `Runner`, call `runner.run(spec)`.
6. If `result.stdout.len > 0`, write it to stdout.
7. If `result.stderr.len > 0`, write it to stderr.
8. Call `std.process.exit(result.exit_code)` — not `return`, so the GPA deinit is intentionally leaked (matches Rust's `std::process::exit()`). Alternatively, defer `result.deinit()` and `runner.deinit()` before `std.process.exit`.

## 5. Prompt Trimming and Empty Rejection

`src/prompt.zig`:

- `trim(prompt: []const u8) []const u8` — returns a subslice with leading/trailing whitespace removed. Pure byte-level, no allocation (Zig `std.mem.trim` operates on slices).
- `build_prompt_spec` calls `std.mem.trim(u8, prompt, " \t\n\r")`, checks length, allocates the trimmed copy, builds the `CommandSpec`.

Error: `error.EmptyPrompt` (or a custom error set `BuildPromptSpecError { EmptyPrompt, OutOfMemory }`).

## 6. Error Format

On subprocess spawn failure:

```
failed to start <argv[0]>: <os_error_description>
```

- `argv[0]` only, not the full command line.
- Example: `failed to start nonexistent_binary: FileNotFound\n`
- Zig's `error.FileNotFound` and friends map naturally. Use `@errorName(err)` or construct a descriptive string.

## 7. Exit Code Forwarding

The `ccc` binary forwards the child's exit code via `std.process.exit()`. This bypasses deferred destructors. To keep it clean:

```zig
const exit_code = result.exit_code;
result.deinit(gpa);
runner.deinit();
std.process.exit(exit_code);
```

Signal exits → exit code 1 (consistent with all other implementations).

## 8. Test Strategy

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

Run via `zig build test`.

### CCC_REAL_OPENCODE override

In tests that spawn real subprocesses, the `CommandSpec` has its `argv[0]` replaced with the value of env `CCC_REAL_OPENCODE` (or a test-specific binary path). This is handled at the test level, not baked into the library — the library takes whatever `argv[0]` is given.

### Cross-language contract tests

The Zig `ccc` binary must be buildable and invocable by `tests/test_ccc_contract.py`. Add a Zig section to each contract test method:

```python
subprocess.run(
    ["zig", "build", "install", "--prefix", str(tmp_path / "zig-install")],
    cwd=ROOT / "zig",
    ...
)
self.assert_equal_output(
    subprocess.run(
        [str(tmp_path / "zig-install" / "bin" / "ccc"), PROMPT],
        ...
    )
)
```

Alternatively, a Makefile in `zig/` for `build/ccc` similar to `c/Makefile`.

## 9. Zig-Specific Considerations

### Comptime

- The error set for `build_prompt_spec` can be comptime-known: `error{EmptyPrompt}` plus any allocator errors.
- No need for runtime type introspection. All types are structs with known layouts.

### Allocators

- The library API takes an `allocator` parameter (no global allocator).
- The CLI binary uses `std.heap.GeneralPurposeAllocator` for its own allocations.
- `CommandSpec` fields that are borrowed (`argv` items, optional `cwd`, `stdin_text`) are `[]const u8` slices — the caller retains ownership.
- `CompletedRun.stdout` and `CompletedRun.stderr` are allocator-owned `[]u8` slices freed via `deinit()`.

### Error Unions

- `build_prompt_spec` returns `!CommandSpec`.
- `Runner.run` returns `!CompletedRun` (spawn errors become in-band stderr in the `CompletedRun`, matching Rust/Python behavior — so `run` actually returns `CompletedRun` directly, not an error union, similar to how Python catches `OSError` internally).
- Decision: `Runner.run` returns `CompletedRun` (no error union). Startup failures are encoded as `exit_code: 1` + stderr message, exactly like all other implementations. Only allocation failures propagate as errors.

### No Hidden Control Flow

- No exceptions, no panics in library code.
- `std.process.exit()` is called exactly once, in the CLI main, with explicit intent.
- No `defer` trickery that could mask errors.

### Slices vs. Owned Strings

- Zig uses `[]const u8` for string-like data. No implicit copies.
- `std.mem.trim` returns a subslice (no allocation). The trimmed result is copied only when building the `CommandSpec` argv.

## 10. Parity Gaps to Watch For

| Concern | Status |
|---------|--------|
| `Runner.stream` | Not in v1. Matches C. Can add later using `std.process.Child` fd polling. |
| `env` merge semantics | Library adds env overrides on top of current process env, matching Python/Rust/TS. Must verify Zig `Child.spawn` behavior with `env_map`. |
| Stdin piping | `std.process.Child` supports `.stdin = .pipe`. Write `stdin_text` then close the pipe. |
| CWD handling | `Child.spawn` accepts `cwd` parameter. Pass through from `CommandSpec.cwd`. |
| Exit code on signal | Map `Term.Signal`/`Term.Stopped` to exit code 1. |
| Error format exactness | Must be `"failed to start <argv[0]>: <...>"` — match Rust/Python/C verbatim. |
| CCC_REAL_OPENCODE | Not in the library. The CLI reads it and patches `argv[0]` before calling the runner. Matches C implementation. |
| Cross-language test integration | Need to add Zig entries to `tests/test_ccc_contract.py` or ensure `zig build` produces a `ccc` binary at a predictable path. |
| `build.zig.zon` minimum Zig version | Pin to a stable release (0.13+). Use `std.Build` API. |
| `std.process.Child` on non-POSIX | Zig supports Windows. `std.process.exit` works cross-platform. Test matrix is POSIX-only for now per existing convention. |

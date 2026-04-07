# C++ Implementation Plan

## 1. Project Structure

```
cpp/
  CMakeLists.txt
  include/
    ccc/
      command_spec.hpp    -- CommandSpec struct
      completed_run.hpp   -- CompletedRun struct
      build_prompt.hpp    -- build_prompt_spec free function
      runner.hpp          -- Runner class (run + stream)
  src/
    command_spec.cpp      -- CommandSpec impl (if needed beyond header)
    completed_run.cpp     -- CompletedRun impl (if needed beyond header)
    build_prompt.cpp      -- build_prompt_spec: trim, reject empty, return CommandSpec
    runner.cpp            -- Runner::run / Runner::stream with POSIX fork/exec
    ccc_cli.cpp           -- main() for ccc binary
  tests/
    CMakeLists.txt
    test_prompt_spec.cpp      -- build_prompt_spec unit tests
    test_runner.cpp           -- Runner unit tests (injectable executor)
    test_ccc_contract.cpp     -- ccc CLI contract tests (mirrors tests/test_ccc_contract.py)
```

### Build System: CMake

- Minimum CMake 3.16, C++17 required
- Two targets: `ccc_lib` (static library) and `ccc` (executable linking it)
- Tests enabled via `option(CCC_BUILD_TESTS "Build tests" ON)`
- Test framework: GoogleTest via `FetchContent` (no system dependency)
- Install targets for the library, headers, and `ccc` binary

```cmake
cmake_minimum_required(VERSION 3.16)
project(call-coding-clis LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(ccc_lib
  src/build_prompt.cpp
  src/runner.cpp
)
target_include_directories(ccc_lib PUBLIC include)

add_executable(ccc src/ccc_cli.cpp)
target_link_libraries(ccc PRIVATE ccc_lib)

# Tests
option(CCC_BUILD_TESTS "Build tests" ON)
if(CCC_BUILD_TESTS)
  include(FetchContent)
  FetchContent_Declare(googletest GIT_REPOSITORY https://github.com/google/googletest.git GIT_TAG v1.14.0)
  FetchContent_MakeAvailable(googletest)

  add_executable(ccc_tests
    tests/test_prompt_spec.cpp
    tests/test_runner.cpp
    tests/test_ccc_contract.cpp
  )
  target_link_libraries(ccc_tests PRIVATE ccc_lib GTest::gtest_main)
  include(GoogleTest)
  gtest_discover_tests(ccc_tests)
endif()
```

## 2. Library API

### `CommandSpec` (`include/ccc/command_spec.hpp`)

```cpp
struct CommandSpec {
    std::vector<std::string> argv;
    std::optional<std::string> stdin_text;
    std::optional<std::filesystem::path> cwd;
    std::map<std::string, std::string> env;
};
```

- Plain struct, moveable, copyable (matches Python dataclass / Rust derive).
- `std::optional` for nullable fields (stdin_text, cwd). Empty env map = inherit parent.

### `CompletedRun` (`include/ccc/completed_run.hpp`)

```cpp
struct CompletedRun {
    std::vector<std::string> argv;
    int exit_code;
    std::string stdout;
    std::string stderr;
};
```

- Holds captured output after a run completes.
- Member names `stdout`/`stderr` shadow the C library names. If that causes issues with macros, use `out_stdout`/`out_stderr` or a namespace.

### `Runner` (`include/ccc/runner.hpp`)

```cpp
using StreamCallback = std::function<void(std::string_view stream_name, std::string_view data)>;

class Runner {
public:
    Runner();
    explicit Runner(std::function<CompletedRun(const CommandSpec&)> executor);

    CompletedRun run(const CommandSpec& spec);
    CompletedRun stream(const CommandSpec& spec, StreamCallback on_event);
};
```

- `run` blocks, captures all stdout/stderr, returns `CompletedRun`.
- `stream` emits chunks via `on_event("stdout", chunk)` / `on_event("stderr", chunk)` then returns the final `CompletedRun`.
- Injectable executor (constructor overload) for unit testing, matching the Python/Rust pattern.

### `build_prompt_spec` (`include/ccc/build_prompt.hpp`)

```cpp
std::optional<CommandSpec> build_prompt_spec(std::string_view prompt);
```

- Returns `std::nullopt` for empty/whitespace-only prompts (instead of throwing, aligning with the C++ idiom of optional for fallible value construction).
- Trims leading/trailing whitespace.
- Returns `CommandSpec{argv={"opencode", "run", trimmed_prompt}}`.

## 3. ccc CLI Binary (`src/ccc_cli.cpp`)

```
Usage: ccc "<Prompt>"
```

Logic:
1. If `argc != 2`: write `"usage: ccc \"<Prompt>\""` to stderr, exit 1.
2. Read `CCC_REAL_OPENCODE` env var; if set, use as the binary name instead of `"opencode"`.
3. Call `build_prompt_spec(argv[1])`. If nullopt, write `"prompt must not be empty"` to stderr, exit 1.
4. Construct `CommandSpec` with the runner override and call `Runner::run(spec)`.
5. Write `result.stdout` to stdout (if non-empty), `result.stderr` to stderr (if non-empty).
6. Call `std::exit(result.exit_code)` to forward the child exit code (matching Rust's `std::process::exit`).

## 4. Subprocess Spawning

Use POSIX `fork`/`execvp` with `pipe()` for stdin/stdout/stderr capture. Rationale:

- `std::process` is not in the C++ standard until C++26 (P2944) and has no widely-available implementation yet.
- POSIX fork/exec gives full control over pipe management, CWD, and environment.
- RAII wrappers will manage pipe file descriptors (custom `Fd` class with `close()` in destructor).

### Implementation outline (`src/runner.cpp`):

1. Create three `pipe()` pairs: stdin (parent writes, child reads), stdout (child writes, parent reads), stderr (child writes, parent reads).
2. `fork()`. In the child:
   - `chdir(cwd)` if specified.
   - Set environment from `spec.env` merged with `environ`.
   - `dup2` pipe ends onto STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO.
   - Close all pipe fds.
   - `execvp(spec.argv[0], argv_array)`. If exec fails: `dprintf(STDERR_FILENO, "failed to start %s: %s\n", argv[0], strerror(errno))`, then `_exit(127)`.
3. In the parent:
   - Close child-end fds.
   - If `stdin_text` is set, write it all to the stdin write fd, then close it.
   - `read()` from stdout and stderr fds into `std::string` buffers (or use `select`/`poll` if implementing true streaming).
   - `waitpid()` for the child.
   - Construct `CompletedRun` with captured output and `WEXITSTATUS` / `WIFEXITED`.

### RAII pipe helper:

```cpp
class Fd {
    int fd_;
public:
    explicit Fd(int fd) : fd_(fd) {}
    ~Fd() { if (fd_ >= 0) ::close(fd_); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
    Fd(Fd&& o) noexcept : fd_(std::exchange(o.fd_, -1)) {}
    int get() const { return fd_; }
};
```

### Streaming strategy:

For the initial implementation, `stream()` can delegate to `run()` and emit a single `"stdout"` / `"stderr"` event with the full buffer after completion (matching Rust's current non-streaming stream). A true line-by-line streaming implementation using `poll()` or `select()` on the two read fds can follow later.

## 5. Prompt Trimming, Empty Rejection

In `build_prompt_spec`:

1. `std::string_view prompt_sv = prompt;`
2. Skip leading whitespace: `prompt_sv.remove_prefix(...)`.
3. Skip trailing whitespace: `prompt_sv.remove_suffix(...)`.
4. If `prompt_sv.empty()`, return `std::nullopt`.
5. Return `CommandSpec{.argv = {"opencode", "run", std::string(prompt_sv)}}`.

This is consistent with Python's `.strip()`, Rust's `.trim()`, and TypeScript's `.trim()`.

## 6. Error Format

When `execvp` fails in the child process:

```
failed to start <argv[0]>: <strerror(errno)>
```

When `Runner::run` catches a failure to `fork()` or create pipes, the `CompletedRun.stderr` should be:

```
failed to start <argv[0]>: <error description>
```

Only `argv[0]` is used, not the full argument vector. This matches Python, Rust, and TypeScript.

## 7. Exit Code Forwarding

- `ccc` CLI: `std::exit(result.exit_code)` to ensure the process exits with the child's code even if destructors would otherwise return `main()` with 0.
- `CompletedRun::exit_code`: extracted via `WIFEXITED(status) ? WEXITSTATUS(status) : 1` (matching C and Rust patterns).
- Signaled children default to exit code 1.

## 8. Test Strategy

### Framework: GoogleTest (gtest)

- Fetched via CMake `FetchContent` -- no system install required.
- Tests discovered automatically via `gtest_discover_tests`.

### Unit tests (`tests/test_prompt_spec.cpp`, `tests/test_runner.cpp`)

These mirror `tests/test_runner.py` and `tests/rust_runner.rs`:

- `build_prompt_spec` returns valid `CommandSpec` with correct argv for a normal prompt.
- `build_prompt_spec` returns `nullopt` for empty string and whitespace-only string.
- `Runner` with injected executor returns correct `CompletedRun`.
- `Runner` reports startup failure for nonexistent binary (stderr contains `"failed to start"` and the argv[0] name).
- `Runner::stream` emits events and returns exit code.
- `CommandSpec` holds stdin_text, cwd, env correctly.

### Contract tests (`tests/test_ccc_contract.cpp`)

These mirror `tests/test_ccc_contract.py` but execute the `ccc` binary as a subprocess:

- **Happy path**: write an `opencode` stub script to a temp dir, set `CCC_REAL_OPENCODE`, run `ccc "Fix the failing tests"`, assert stdout is `"opencode run Fix the failing tests\n"` and exit code 0.
- **Empty prompt**: run `ccc ""`, assert exit code 1, stdout empty, stderr non-empty.
- **Missing prompt**: run `ccc` with no args, assert exit code 1, stderr contains `ccc "<Prompt>"`.
- **Whitespace-only prompt**: run `ccc "   "`, assert exit code 1, stdout empty, stderr non-empty.

### `CCC_REAL_OPENCODE` support

- Read `CCC_REAL_OPENCODE` env var in `ccc_cli.cpp`. If set, use its value as the first element of argv (replacing `"opencode"`).
- Contract tests set this to point to a stub script.

### Test execution

```bash
cd cpp && mkdir -p build && cd build
cmake .. -DCCC_BUILD_TESTS=ON
cmake --build .
ctest --output-on-failure
```

## 9. C++-Specific Considerations

### RAII for file descriptors

The `Fd` class ensures pipe fds are closed even when exceptions or early returns occur. This is the biggest correctness win over the C implementation, where manual close-on-every-path is error-prone.

### Smart pointers

Not heavily needed -- `CommandSpec` and `CompletedRun` are value types with `std::string`/`std::vector` members. The `Runner` class stores a `std::function` for the injectable executor, which handles ownership internally.

### Templates

Not required for the core API. If a `build_prompt_spec` overload for different prompt types is desired, a simple function template or `std::string_view` parameter covers it. Avoid over-templating -- the Rust and Python implementations are concrete, not generic.

### `std::filesystem`

Used for the optional `cwd` field in `CommandSpec` (`std::filesystem::path`). No filesystem traversal is needed in the library itself.

### `std::optional`

Used for `build_prompt_spec` return type and optional fields in `CommandSpec` (stdin_text, cwd). This is the idiomatic C++17 replacement for nullable pointers or exceptions for expected failures.

### `std::string_view`

Used for the `prompt` parameter in `build_prompt_spec` and for `StreamCallback` chunk arguments. Avoids copies for string passing.

### No exceptions in hot paths

The library should not throw for expected conditions (empty prompt, nonexistent binary). Use `std::optional` for fallible returns and error strings in `CompletedRun.stderr` for subprocess failures. Only throw for truly unexpected bugs (logic errors).

### Move semantics

`CommandSpec` and `CompletedRun` should be moveable. The `Runner` class is not copyable but is moveable. Construct specs with brace-init and move them into `run()`.

## 10. Parity Gaps to Watch For

### Missing features to implement (matching minimum contract)

| Feature | Status in C++ plan |
|---------|-------------------|
| `build_prompt_spec` | Planned |
| `Runner::run` | Planned |
| `Runner::stream` | Planned (non-streaming fallback, like Rust) |
| `ccc` CLI binary | Planned |
| Prompt trimming | Planned |
| Empty prompt rejection | Planned |
| Stdin/CWD/Env support | Planned |
| Startup failure reporting | Planned |
| Exit code forwarding | Planned |
| `CCC_REAL_OPENCODE` | Planned |

### Features other languages have that C++ should NOT implement yet

- `CCC_RUNNER_PREFIX_JSON` (TypeScript only) -- not in contract.
- Streaming CLI output (TypeScript only) -- not in contract.
- True line-by-line streaming (Python/TypeScript have it; Rust has non-streaming fallback) -- defer to v2.

### Gaps vs C implementation (closest reference)

- C has no `Runner::stream`. C++ should include `stream()` in the API from day one (even if non-streaming internally) for cross-language API consistency.
- C's `ccc_build_prompt_command` returns a formatted command string. C++ should use `CommandSpec` directly (matching Python/Rust/TypeScript), not a string.

### Potential pitfalls

1. **argv[0] in error messages**: Must use only `spec.argv[0]`, not the full command line. Verify in the child exec-failure path and the fork-failure path.
2. **Temporary file cleanup**: Unlike the C implementation (which uses mkstemp temp files), use `pipe()` directly to avoid temp file leakage. RAII `Fd` class handles cleanup.
3. **Environment merging**: When `spec.env` is non-empty, merge with `environ` (from `<unistd.h>`), not replace it entirely. Use `std::map<std::string, std::string>` and iterate.
4. **Large output**: `read()` into a growing `std::string` in a loop. Use a 4096-byte buffer per read.
5. **EINTR handling**: Retry `read()` and `write()` on `EINTR`.
6. **Child stdin close**: After writing stdin_text to the child's stdin pipe, close the write end so the child sees EOF.

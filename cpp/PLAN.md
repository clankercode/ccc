# C++ Implementation Plan

## 1. Project Structure

```
cpp/
  CMakeLists.txt
  include/
    ccc/
      ccc.hpp              -- Umbrella header: includes all public API
      command_spec.hpp      -- CommandSpec struct
      completed_run.hpp     -- CompletedRun struct
      build_prompt.hpp      -- build_prompt_spec free function
      runner.hpp            -- Runner class (run + stream)
  src/
    build_prompt.cpp        -- build_prompt_spec: trim, reject empty, return CommandSpec
    runner.cpp              -- Runner default executor: POSIX fork/exec with pipes
    ccc_cli.cpp             -- main() for ccc binary
  tests/
    CMakeLists.txt
    test_prompt_spec.cpp      -- build_prompt_spec unit tests
    test_runner.cpp           -- Runner unit tests (injectable executor)
    test_ccc_contract.cpp     -- ccc CLI contract tests (mirrors tests/test_ccc_contract.py)
```

## 2. Build System: CMake

Minimum CMake 3.16, C++17 required.

Two targets: `ccc_lib` (static library) and `ccc` (executable linking it).
Tests enabled via `option(CCC_BUILD_TESTS "Build tests" ON)`.
Test framework: GoogleTest via `FetchContent` (no system dependency).

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

option(CCC_BUILD_TESTS "Build tests" ON)
if(CCC_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

install(TARGETS ccc RUNTIME DESTINATION bin)
install(TARGETS ccc_lib ARCHIVE DESTINATION lib)
install(DIRECTORY include/ccc DESTINATION include)
```

### `tests/CMakeLists.txt`

```cmake
include(FetchContent)
FetchContent_Declare(googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG v1.14.0
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(ccc_tests
  test_prompt_spec.cpp
  test_runner.cpp
  test_ccc_contract.cpp
)
target_link_libraries(ccc_tests PRIVATE ccc_lib GTest::gtest_main)
include(GoogleTest)
gtest_discover_tests(ccc_tests)
```

## 3. Build Instructions

### Prerequisites

- CMake >= 3.16
- A C++17-capable compiler (GCC >= 8, Clang >= 7, MSVC >= 2019)
- Internet access (first build fetches GoogleTest; subsequent builds use CMake cache)

### Build

```bash
cd cpp
mkdir -p build && cd build
cmake .. -DCCC_BUILD_TESTS=ON
cmake --build . --parallel
```

### Test

```bash
cd cpp/build
ctest --output-on-failure
```

Or run the test binary directly for verbose output:

```bash
./ccc_tests --gtest_print_time=0
```

### Install

```bash
cmake --install . --prefix /usr/local
```

### Clean

```bash
cmake --build . --target clean
# or
rm -rf build
```

## 4. Library API

### Umbrella Header (`include/ccc/ccc.hpp`)

```cpp
#include <ccc/command_spec.hpp>
#include <ccc/completed_run.hpp>
#include <ccc/build_prompt.hpp>
#include <ccc/runner.hpp>
```

Consumers can `#include <ccc/ccc.hpp>` to get the full public API.

### `CommandSpec` (`include/ccc/command_spec.hpp`)

```cpp
#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

struct CommandSpec {
    std::vector<std::string> argv;
    std::optional<std::string> stdin_text;
    std::optional<std::filesystem::path> cwd;
    std::map<std::string, std::string> env;
};
```

Builder methods (matches Rust's `with_stdin`/`with_cwd`/`with_env` pattern):

```cpp
inline CommandSpec make_command_spec(std::vector<std::string> argv) {
    return CommandSpec{std::move(argv), std::nullopt, std::nullopt, {}};
}

inline CommandSpec& with_stdin(CommandSpec& spec, std::string text) {
    spec.stdin_text = std::move(text);
    return spec;
}

inline CommandSpec& with_cwd(CommandSpec& spec, std::filesystem::path dir) {
    spec.cwd = std::move(dir);
    return spec;
}

inline CommandSpec& with_env(CommandSpec& spec, std::string key, std::string value) {
    spec.env[std::move(key)] = std::move(value);
    return spec;
}
```

Each `with_*` returns a reference to allow chaining:
```cpp
auto spec = with_stdin(with_cwd(with_env(make_command_spec({"cmd"}), "K", "V"), "/tmp"), "hello");
```

Design notes:
- Plain struct, moveable, copyable (matches Python dataclass / Rust derive).
- `std::optional` for nullable fields (stdin_text, cwd). Empty env map = inherit parent.
- Builder functions are free functions taking a reference (not member methods) to keep the struct POD-like and header-only. Alternatively, they can be non-member inline functions.

### `CompletedRun` (`include/ccc/completed_run.hpp`)

```cpp
#include <string>
#include <vector>

struct CompletedRun {
    std::vector<std::string> argv;
    int exit_code = 0;
    std::string out_stdout;
    std::string out_stderr;
};
```

Member names use `out_stdout`/`out_stderr` to avoid shadowing the POSIX `stdout`/`stderr` macros (which are `FILE*` objects defined as macros on some platforms). This is safer than relying on `#include` ordering.

### `Runner` (`include/ccc/runner.hpp`)

```cpp
#include <ccc/command_spec.hpp>
#include <ccc/completed_run.hpp>
#include <functional>
#include <string_view>

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
- Default constructor creates a `Runner` with the real POSIX fork/exec executor.
- The `Runner` is moveable but not copyable (same as Rust's `Box<dyn Fn>` pattern).

### `build_prompt_spec` (`include/ccc/build_prompt.hpp`)

```cpp
#include <ccc/command_spec.hpp>
#include <optional>
#include <string_view>

std::optional<CommandSpec> build_prompt_spec(std::string_view prompt);
```

- Returns `std::nullopt` for empty/whitespace-only prompts (aligning with C++17 optional-for-fallible-value idiom).
- Trims leading/trailing whitespace.
- Returns `CommandSpec{argv={"opencode", "run", trimmed_prompt}}`.

## 5. ccc CLI Binary (`src/ccc_cli.cpp`)

```
Usage: ccc "<Prompt>"
```

Logic:
1. If `argc != 2`: write `usage: ccc "<Prompt>"\n` to stderr, exit 1.
2. Call `build_prompt_spec(argv[1])`. If `nullopt`, write `prompt must not be empty\n` to stderr, exit 1.
3. Read `CCC_REAL_OPENCODE` env var via `std::getenv`. If set, replace `spec.argv[0]` with its value. This allows contract tests to override the binary without modifying PATH (matching the C implementation's approach).
4. Construct `Runner()` (default) and call `Runner::run(spec)`.
5. Write `result.out_stdout` to stdout (if non-empty), `result.out_stderr` to stderr (if non-empty).
6. Call `std::exit(result.exit_code)` to forward the child exit code.

**Why `CCC_REAL_OPENCODE` replaces argv[0] instead of the plan reading it before `build_prompt_spec`:**
`build_prompt_spec` always produces `argv[0] = "opencode"`. The CLI then overrides this if `CCC_REAL_OPENCODE` is set. This matches the C implementation (`c/src/ccc.c:48-51`) where the env var is checked after prompt validation but before execution.

**Why `std::exit` instead of `return`:**
Ensures the process exits with the child's code even if destructors would otherwise cause `main()` to return 0. Matches Rust's `std::process::exit()`.

## 6. Subprocess Spawning

Use POSIX `fork`/`execvp` with `pipe()` for stdin/stdout/stderr capture. Rationale:

- `std::process` is not in the C++ standard until C++26 (P2944) and has no widely-available implementation yet.
- POSIX fork/exec gives full control over pipe management, CWD, and environment.
- RAII wrappers manage pipe file descriptors.

### RAII File Descriptor Helper

```cpp
#include <unistd.h>
#include <utility>

class Fd {
    int fd_;
public:
    explicit Fd(int fd = -1) : fd_(fd) {}
    ~Fd() { if (fd_ >= 0) ::close(fd_); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
    Fd(Fd&& o) noexcept : fd_(std::exchange(o.fd_, -1)) {}
    Fd& operator=(Fd&& o) noexcept {
        if (this != &o) {
            if (fd_ >= 0) ::close(fd_);
            fd_ = std::exchange(o.fd_, -1);
        }
        return *this;
    }
    int get() const { return fd_; }
    explicit operator bool() const { return fd_ >= 0; }
};
```

### POSIX Write-All Helper

Handles partial writes and `EINTR` (matching the C implementation's `ccc_write_all`):

```cpp
#include <cerrno>
#include <cstring>

bool write_all(int fd, const std::string& data) {
    size_t remaining = data.size();
    const char* cursor = data.data();
    while (remaining > 0) {
        ssize_t written = ::write(fd, cursor, remaining);
        if (written < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (written == 0) return false;  // pipe closed; guard against infinite loop
        cursor += written;
        remaining -= static_cast<size_t>(written);
    }
    return true;
}
```

### Default Executor Implementation (`src/runner.cpp`)

```cpp
#include <ccc/runner.hpp>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <map>
#include <sstream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char** environ;

namespace {

std::vector<std::string> make_env_array(const std::map<std::string, std::string>& overrides) {
    std::vector<std::string> result;
    if (overrides.empty()) return result;
    for (size_t i = 0; environ[i] != nullptr; ++i) {
        std::string entry = environ[i];
        auto eq = entry.find('=');
        if (eq == std::string::npos) continue;
        auto key = entry.substr(0, eq);
        if (overrides.count(key)) continue;  // overridden below
        result.push_back(entry);
    }
    for (const auto& [k, v] : overrides) {
        result.push_back(k + "=" + v);
    }
    return result;
}

std::vector<char*> to_c_argv(const std::vector<std::string>& args) {
    std::vector<char*> result;
    for (auto& s : args) {
        result.push_back(const_cast<char*>(s.c_str()));
    }
    result.push_back(nullptr);
    return result;
}

CompletedRun failed_run(const CommandSpec& spec, const std::string& error) {
    return CompletedRun{
        spec.argv,
        1,
        std::string(),
        "failed to start " + spec.argv[0] + ": " + error + "\n"
    };
}

}  // namespace

Runner::Runner() : executor_([](const CommandSpec& spec) -> CompletedRun {
    // See implementation outline below
    return CompletedRun{spec.argv, 1, "", "not implemented"};
}) {}

Runner::Runner(std::function<CompletedRun(const CommandSpec&)> executor)
    : executor_(std::move(executor)) {}

CompletedRun Runner::run(const CommandSpec& spec) {
    return executor_(spec);
}

CompletedRun Runner::stream(const CommandSpec& spec, StreamCallback on_event) {
    CompletedRun result = run(spec);
    if (!result.out_stdout.empty()) {
        on_event("stdout", result.out_stdout);
    }
    if (!result.out_stderr.empty()) {
        on_event("stderr", result.out_stderr);
    }
    return result;
}
```

### Executor Implementation Outline

The default executor (stored in `Runner::executor_`) does the following:

1. **Validate argv**: If `spec.argv.empty()` or `spec.argv[0].empty()`, return `failed_run(spec, "empty command")`.

2. **Create pipes**: Three `pipe()` calls for stdin, stdout, stderr. Wrap all fds in `Fd` RAII objects immediately. If any `pipe()` fails, return `failed_run(spec, std::strerror(errno))`.

3. **Fork**:
   - If `fork()` fails, return `failed_run(spec, std::strerror(errno))`.
   - In the **child process**:
     a. If `spec.cwd` is set, call `chdir(spec.cwd->c_str())`. If it fails, `_exit(127)`.
     b. If `spec.env` is non-empty, build the merged environment and call `execvpe` (GNU extension) or iterate `environ` + overrides to build a `std::vector<std::string>` and convert to `char**` for `execve`. If neither is available, fall back to modifying `environ` via `setenv` before exec.
     c. `dup2` pipe ends onto `STDIN_FILENO`, `STDOUT_FILENO`, `STDERR_FILENO`.
     d. Close all pipe fds (RAII destructors run, but explicit close after dup2 is fine too).
     e. If `stdin_text` is not set, dup2 `/dev/null` onto `STDIN_FILENO` (prevents child from inheriting the parent's stdin — matches C implementation).
     f. `execvp(spec.argv[0], argv_array)`. If exec fails: `dprintf(STDERR_FILENO, "failed to start %s: %s\n", argv[0], strerror(errno))`, then `_exit(127)`.
     g. **Critical**: Use `_exit()`, never `exit()`, in the child to avoid flushing parent's stdio buffers.
   - In the **parent process**:
     a. Close child-end pipe fds (they are held in `Fd` objects — either scope-close or move-into-discard).
     b. If `spec.stdin_text` is set, call `write_all()` on the stdin write fd. If write fails, close pipes and `waitpid` the child, then return a failure run.
     c. Close the stdin write fd (signals EOF to child).
     d. Read stdout and stderr into `std::string` buffers. Use `poll()` or `select()` to read from both without deadlocking (see Deadlock Avoidance below).
     e. `waitpid()` for the child. Retry on `EINTR`.
     f. Extract exit code: `WIFEXITED(status) ? WEXITSTATUS(status) : 1`.
     g. Return `CompletedRun{spec.argv, exit_code, stdout_str, stderr_str}`.

### Deadlock Avoidance

Reading stdout and stderr sequentially can deadlock if the child writes enough to one pipe to fill the OS buffer (typically 64KB) while the other pipe still has unread data. Solution:

```cpp
#include <poll.h>
#include <unistd.h>

std::pair<std::string, std::string> read_pipes(int stdout_fd, int stderr_fd) {
    std::string out, err;
    std::array<char, 4096> buf;
    struct pollfd fds[2] = {{stdout_fd, POLLIN, 0}, {stderr_fd, POLLIN, 0}};

    while (fds[0].fd >= 0 || fds[1].fd >= 0) {
        int ready = ::poll(fds, 2, -1);
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        for (int i = 0; i < 2; ++i) {
            if (fds[i].fd < 0) continue;
            if (fds[i].revents & (POLLIN | POLLHUP)) {
                ssize_t n = ::read(fds[i].fd, buf.data(), buf.size());
                if (n > 0) {
                    (i == 0 ? out : err).append(buf.data(), static_cast<size_t>(n));
                } else {
                    fds[i].fd = -1;  // EOF or error
                }
            }
            if (fds[i].revents & (POLLERR | POLLNVAL)) {
                fds[i].fd = -1;
            }
        }
    }
    return {out, err};
}
```

This is the single most important correctness improvement over a naive sequential `read()` approach. The C implementation avoids this by using temp files instead of pipes, but pipes are preferred for the C++ implementation (no disk I/O, no temp-file cleanup).

### Streaming Strategy

For the initial implementation, `stream()` delegates to `run()` and emits a single `"stdout"` / `"stderr"` event with the full buffer after completion (matching Rust's current non-streaming stream). A true line-by-line streaming implementation using `poll()` + callbacks on the two read fds can follow later.

## 7. Prompt Trimming and Empty Rejection

In `build_prompt_spec` (`src/build_prompt.cpp`):

```cpp
#include <ccc/build_prompt.hpp>
#include <cctype>
#include <string>

std::optional<CommandSpec> build_prompt_spec(std::string_view prompt) {
    while (!prompt.empty() && std::isspace(static_cast<unsigned char>(prompt.front()))) {
        prompt.remove_prefix(1);
    }
    while (!prompt.empty() && std::isspace(static_cast<unsigned char>(prompt.back()))) {
        prompt.remove_suffix(1);
    }
    if (prompt.empty()) {
        return std::nullopt;
    }
    std::vector<std::string> argv;
    argv.reserve(3);
    argv.push_back("opencode");
    argv.push_back("run");
    argv.emplace_back(prompt);
    return CommandSpec{std::move(argv), std::nullopt, std::nullopt, {}};
}
```

This is consistent with Python's `.strip()`, Rust's `.trim()`, TypeScript's `.trim()`, and the C implementation's `trim_in_place()`.

## 8. Error Format

When `execvp` fails in the child process:

```
failed to start <argv[0]>: <strerror(errno)>
```

When the parent catches a failure to `fork()` or create pipes, the `CompletedRun.out_stderr` should be:

```
failed to start <argv[0]>: <error description>
```

Only `argv[0]` is used, not the full argument vector. This matches Python, Rust, TypeScript, and C.

The error string always ends with `\n` to match the Python/TypeScript behavior (`"failed to start ...\n"`).

## 9. Exit Code Forwarding

- `ccc` CLI: `std::exit(result.exit_code)` to ensure the process exits with the child's code.
- `CompletedRun::exit_code`: extracted via `WIFEXITED(status) ? WEXITSTATUS(status) : 1` (matching C and Rust patterns).
- Signaled children default to exit code 1.
- Fork failure, pipe failure, or exec failure in the parent: exit code 1 in the `CompletedRun`.

## 10. `CCC_REAL_OPENCODE` Support

The `ccc` CLI binary reads the `CCC_REAL_OPENCODE` environment variable. If set, its value replaces `spec.argv[0]` (which was set to `"opencode"` by `build_prompt_spec`). This allows contract tests to point to a stub script without modifying PATH.

This matches the C implementation (`c/src/ccc.c:48-53`) and is used by the C++ contract tests.

The Python, Rust, and TypeScript contract tests in `test_ccc_contract.py` use a different approach (PATH override with a stub `opencode` binary). Both approaches are valid. The C++ CLI supports `CCC_REAL_OPENCODE` because:
1. It avoids requiring PATH modification (cleaner for subprocess-based tests).
2. It's already established by the C implementation.

## 11. Test Strategy

### Framework: GoogleTest (gtest)

Fetched via CMake `FetchContent` — no system install required.
Tests discovered automatically via `gtest_discover_tests`.

### Unit Tests (`tests/test_prompt_spec.cpp`)

Mirrors `tests/test_runner.py::test_ccc_builds_prompt_command_spec` and `tests/rust_runner.rs::ccc_builds_prompt_command_spec`:

| Test | Description |
|------|-------------|
| `BuildPromptSpec_ReturnsValidSpec` | `build_prompt_spec("Fix the failing tests")` returns `CommandSpec` with `argv == {"opencode", "run", "Fix the failing tests"}` |
| `BuildPromptSpec_RejectsEmpty` | `build_prompt_spec("")` returns `std::nullopt` |
| `BuildPromptSpec_RejectsWhitespace` | `build_prompt_spec("   ")` returns `std::nullopt` |
| `BuildPromptSpec_RejectsTabOnly` | `build_prompt_spec("\t\n")` returns `std::nullopt` |
| `BuildPromptSpec_TrimsLeading` | `build_prompt_spec("  hello  ")` returns argv ending with `"hello"` |
| `BuildPromptSpec_TrimsTrailing` | `build_prompt_spec("hello   ")` returns argv ending with `"hello"` |

### Unit Tests (`tests/test_runner.cpp`)

Mirrors `tests/test_runner.py` and `tests/rust_runner.rs`:

| Test | Description |
|------|-------------|
| `Run_ReturnsCompletedResult` | Inject executor returning known result, verify `Runner::run()` passes through. |
| `Run_UsesStdinAndEnv` | Inject executor, verify the `CommandSpec` fields (stdin_text, env, cwd) are available to the executor. |
| `Stream_EmitsStdoutAndStderrEvents` | Inject stream executor that calls callback, verify events captured and exit code returned. |
| `Run_ReportsMissingBinaryStartFailure` | Use real `Runner` (no injection), run with nonexistent binary, assert exit code != 0, stdout empty, stderr contains `"failed to start"` and the argv[0] name. |
| `Stream_ReportsMissingBinaryStartFailure` | Same but via `Runner::stream()`, also verify events contain a `"stderr"` event with the error. |
| `CommandSpec_HoldsFields` | Verify `CommandSpec` holds stdin_text, cwd, env correctly using builder functions. |
| `BuildPromptSpec_ValidPrompt` | Mirror of `test_ccc_builds_prompt_command_spec`. |
| `BuildPromptSpec_EmptyRejected` | Mirror of `test_ccc_rejects_empty_prompt`. |

### Contract Tests (`tests/test_ccc_contract.cpp`)

These execute the `ccc` binary as a subprocess, mirroring `tests/test_ccc_contract.py`:

| Test | Description |
|------|-------------|
| `Contract_HappyPath` | Write an opencode stub script to a temp dir, set `CCC_REAL_OPENCODE`, run `ccc "Fix the failing tests"`, assert stdout is `"opencode run Fix the failing tests\n"` and exit code 0. |
| `Contract_EmptyPrompt` | Run `ccc ""`, assert exit code 1, stdout empty, stderr non-empty. |
| `Contract_MissingPrompt` | Run `ccc` with no args, assert exit code 1, stderr contains `ccc "<Prompt>"`. |
| `Contract_WhitespacePrompt` | Run `ccc "   "`, assert exit code 1, stdout empty, stderr non-empty. |

The stub script for happy-path tests:

```cpp
// Helper to create a stub opencode script
static std::filesystem::path write_opencode_stub(const std::filesystem::path& dir) {
    auto stub = dir / "opencode";
    std::ofstream f(stub);
    f << "#!/bin/sh\n"
      << "if [ \"$1\" != \"run\" ]; then exit 9; fi\n"
      << "shift\n"
      << "printf 'opencode run %s\\n' \"$1\"\n";
    f.close();
    std::filesystem::permissions(stub,
        std::filesystem::perms::owner_exec |
        std::filesystem::perms::group_exec |
        std::filesystem::perms::others_exec,
        std::filesystem::perm_options::add);
    return stub;
}
```

### Test Execution

```bash
cd cpp && mkdir -p build && cd build
cmake .. -DCCC_BUILD_TESTS=ON
cmake --build . --parallel
ctest --output-on-failure
```

### Disabling Tests (for consumers)

```bash
cmake .. -DCCC_BUILD_TESTS=OFF
```

## 12. Cross-Language Contract Test Registration

To register the C++ `ccc` binary in the shared cross-language contract tests (`tests/test_ccc_contract.py`), add a subprocess block in each `test_cross_language_*` method following the existing pattern.

### Steps

1. Build the C++ `ccc` binary: `cd cpp && mkdir -p build && cd build && cmake .. && cmake --build .`
2. In `tests/test_ccc_contract.py`, add a new subprocess call for C++ in each test method (after the existing language blocks):

```python
# C++
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "cpp/build/ccc"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

3. Repeat for `test_cross_language_ccc_rejects_empty_prompt`, `test_cross_language_ccc_requires_one_prompt_argument`, and `test_cross_language_ccc_rejects_whitespace_only_prompt`.

### Alternative: CCC_REAL_OPENCODE

The C++ contract tests can also use `CCC_REAL_OPENCODE` (which the C++ CLI reads), but the shared `test_ccc_contract.py` uses PATH-based stub injection for all other languages. For consistency, register C++ using the same PATH approach (no `CCC_REAL_OPENCODE` needed in the shared tests). The `CCC_REAL_OPENCODE` path is used by the C++-native gtest contract tests in `tests/test_ccc_contract.cpp`.

## 13. CI Integration

### GitHub Actions (when CI is added)

Add a job for C++ build and test. No existing `.github/workflows/` directory exists yet; create when needed.

```yaml
# .github/workflows/cpp.yml
name: C++
on: [push, pull_request]
jobs:
  cpp-build-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        compiler: [gcc, clang]
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y cmake g++ clang
      - name: Build and test (GCC)
        if: matrix.compiler == 'gcc'
        run: |
          cd cpp && mkdir -p build && cd build
          cmake .. -DCMAKE_CXX_COMPILER=g++ -DCCC_BUILD_TESTS=ON
          cmake --build . --parallel
          ctest --output-on-failure
      - name: Build and test (Clang)
        if: matrix.compiler == 'clang'
        run: |
          cd cpp && mkdir -p build && cd build
          cmake .. -DCMAKE_CXX_COMPILER=clang++ -DCCC_BUILD_TESTS=ON
          cmake --build . --parallel
          ctest --output-on-failure
      - name: Build and test (no tests)
        run: |
          cd cpp && mkdir -p build && cd build
          cmake .. -DCCC_BUILD_TESTS=OFF
          cmake --build . --parallel
```

### Makefile Integration (optional)

If a top-level Makefile is added, add a C++ target:

```makefile
cpp/build/ccc: cpp/src/*.cpp cpp/include/**/*.hpp
	cd cpp && mkdir -p build && cd build && cmake .. && cmake --build .

cpp-test: cpp/build/ccc
	cd cpp/build && ctest --output-on-failure

cpp-clean:
	rm -rf cpp/build
```

## 14. C++-Specific Considerations

### RAII for File Descriptors

The `Fd` class ensures pipe fds are closed even when exceptions or early returns occur. This is the biggest correctness win over the C implementation, where manual close-on-every-path is error-prone.

### Smart Pointers

Not heavily needed — `CommandSpec` and `CompletedRun` are value types with `std::string`/`std::vector` members. The `Runner` class stores a `std::function` for the injectable executor, which handles ownership internally.

### Templates

Not required for the core API. If a `build_prompt_spec` overload for different prompt types is desired, `std::string_view` parameter already covers it. Avoid over-templating — the Rust and Python implementations are concrete, not generic.

### `std::filesystem`

Used for the optional `cwd` field in `CommandSpec` (`std::filesystem::path`) and for creating temp stub scripts in contract tests. No filesystem traversal is needed in the library itself.

### `std::optional`

Used for `build_prompt_spec` return type and optional fields in `CommandSpec` (stdin_text, cwd). This is the idiomatic C++17 replacement for nullable pointers or exceptions for expected failures.

### `std::string_view`

Used for the `prompt` parameter in `build_prompt_spec` and for `StreamCallback` chunk arguments. Avoids copies for string passing.

### No Exceptions in Hot Paths

The library should not throw for expected conditions (empty prompt, nonexistent binary). Use `std::optional` for fallible returns and error strings in `CompletedRun.out_stderr` for subprocess failures. Only throw for truly unexpected bugs (logic errors, out-of-memory).

### Move Semantics

`CommandSpec` and `CompletedRun` are moveable and copyable. The `Runner` class is moveable but not copyable (it holds a `std::function` which may capture state). Construct specs with brace-init and move them into `run()`.

### `_exit()` vs `exit()` in Child Process

After `fork()`, the child must use `_exit()` (from `<unistd.h>`), never `exit()`. Using `exit()` would flush stdio buffers that were duplicated from the parent via fork, causing double output. The plan's executor implementation uses `_exit(127)` for all child error paths.

### `argv` Conversion for `execvp`

`execvp` takes a `char* const[]` (NULL-terminated). The `std::vector<std::string>` in `CommandSpec::argv` must be converted. Use a helper:

```cpp
std::vector<char*> to_c_argv(const std::vector<std::string>& args) {
    std::vector<char*> result;
    for (auto& s : args) {
        result.push_back(const_cast<char*>(s.c_str()));
    }
    result.push_back(nullptr);
    return result;
}
```

Note: `const_cast` is safe here because `execvp` does not modify the argv array (despite the non-const signature in POSIX).

### `execvp` vs `execvpe`

For environment merging, `execvpe` is a GNU extension available on Linux. For portability, build a `std::vector<std::string>` of `"KEY=VALUE"` entries merged with `environ`, convert to `char**`, and use `execve`. If `execvpe` is available, prefer it for simplicity.

```cpp
#if defined(__GNU_SOURCE) || defined(__linux__)
    // execvpe available
    execvpe(argv0, argv_array, envp_array);
#else
    execve(argv0, argv_array, envp_array);
#endif
```

## 15. Parity Gaps to Watch For

### Features matching minimum contract

| Feature | Status |
|---------|--------|
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
| Builder pattern for CommandSpec | Planned (`make_command_spec`, `with_*`) |
| Umbrella header | Planned (`<ccc/ccc.hpp>`) |

### Features other languages have that C++ should NOT implement yet

- `CCC_RUNNER_PREFIX_JSON` (TypeScript only) — not in contract.
- Streaming CLI output (TypeScript only) — not in contract.
- True line-by-line streaming (Python/TypeScript have it; Rust has non-streaming fallback) — defer to v2.

### Gaps vs C implementation (closest reference)

- C has no `Runner::stream`. C++ includes `stream()` in the API from day one (even if non-streaming internally) for cross-language API consistency.
- C's `ccc_build_prompt_command` returns a formatted command string. C++ uses `CommandSpec` directly (matching Python/Rust/TypeScript), not a string.
- C uses temp files for stdout/stderr capture. C++ uses pipes (no disk I/O, no temp-file cleanup, but requires `poll()` to avoid deadlocks).

### Potential Pitfalls

1. **argv[0] in error messages**: Must use only `spec.argv[0]`, not the full command line. Verify in the child exec-failure path and the fork-failure path.
2. **Pipe deadlock**: Reading stdout and stderr sequentially can deadlock. Must use `poll()`/`select()` to interleave reads (see section 6).
3. **Environment merging**: When `spec.env` is non-empty, merge with `environ` — not replace. Empty `spec.env` means inherit parent environment entirely.
4. **Large output**: `read()` into a growing `std::string` in a loop. Use a 4096-byte buffer per read.
5. **EINTR handling**: Retry `read()`, `write()`, `poll()`, and `waitpid()` on `EINTR`.
6. **Child stdin close**: After writing stdin_text to the child's stdin pipe, close the write end so the child sees EOF.
7. **`_exit()` in child**: Never call `exit()` in the child after fork — use `_exit()` to avoid double-flushing stdio buffers.
8. **`SIGPIPE`**: If the child exits before the parent finishes writing stdin, `write()` will fail with `EPIPE`. The `write_all` helper handles this by returning `false`, which the executor treats as a non-fatal write error (the child already exited, so `waitpid` will collect its status).
9. **`stdout`/`stderr` macro collision**: `CompletedRun` uses `out_stdout`/`out_stderr` member names to avoid conflicting with POSIX macros.
10. **`poll()` not available everywhere**: `poll()` is POSIX. On systems without it (unlikely for modern Linux/macOS), `select()` is the fallback. For C++17 targeting Linux/macOS, `poll()` is always available.

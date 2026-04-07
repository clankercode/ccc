# Cross-Language Test Harness Plan

## Problem

The current contract tests in `tests/test_ccc_contract.py` use a trivial shell stub
that only checks `$1 == "run"` and echoes. This is insufficient to detect real
behavioral differences between language implementations:

- **Exit code forwarding** — Does the implementation correctly forward non-zero
  exit codes from the underlying runner binary?
- **Stderr forwarding** — Is stderr from the runner binary captured and
  surfaced intact?
- **Stdin passthrough** — When a `CommandSpec` includes `stdin_text`, is it
  actually piped to the child process?
- **Environment variable overrides** — Does `CCC_REAL_OPENCODE` (or equivalent)
  correctly replace the default binary?
- **Argument quoting** — Are prompts containing spaces, special characters,
  or embedded quotes handled identically?
- **Large output** — Do all implementations handle multi-kilobyte stdout/stderr
  without truncation or buffering artifacts?
- **Stream vs run parity** — When an implementation supports both `run` and
  `stream`, do they produce identical `CompletedRun` results?

## Solution: `mock-coding-cli`

A purpose-built, deterministic mock binary that replaces `opencode` during
testing. It reacts to known prompts with pre-defined responses covering all
the behavioral dimensions above.

### Mock Binary Design

**Location:** `tests/mock-coding-cli/` (compiled or interpreted, likely a
small POSIX shell script or C binary for portability)

**Protocol:** The mock reads its argv and optional stdin, then produces a
deterministic response based on a built-in prompt table.

#### Prompt Table (built into the mock)

| Prompt/Trigger | Exit Code | Stdout | Stderr | Notes |
|---|---|---|---|---|
| `hello world` | 0 | `mock: ok\n` | (empty) | Basic happy path |
| `Fix the failing tests` | 0 | `opencode run Fix the failing tests\n` | (empty) | Backward compat with existing stub |
| `exit 42` | 42 | (empty) | `mock: intentional failure\n` | Non-zero exit code forwarding |
| `stderr test` | 0 | `mock: stdout output\n` | `mock: stderr output\n` | Stderr forwarding |
| `multiline` | 0 | `line1\nline2\nline3\n` | (empty) | Multi-line stdout |
| `large output` | 0 | 4096+ chars of `A` repeated | (empty) | Large output handling |
| `mixed streams` | 1 | `mock: out\n` | `mock: err\n` | Both streams + non-zero |
| (stdin contains `PROMPT:`) | 0 | `mock: stdin received: <text after PROMPT:>` | (empty) | Stdin echo test |
| (no args) | 1 | (empty) | `usage: opencode run "<Prompt>"` | Missing args |
| (any other) | 0 | `mock: unknown prompt '<args>'\n` | (empty) | Catch-all |

#### Stdin Behavior

If stdin is non-empty and starts with `PROMPT:`, the mock echoes the remainder
to stdout (regardless of argv). This lets us test stdin passthrough without
relying on argv content.

### Test Harness Architecture

**Location:** `tests/test_harness.py`

```
tests/
  mock-coding-cli/
    mock_coding_cli.sh       # The mock binary (or compiled)
  test_harness.py             # New harness
  test_ccc_contract.py        # Existing (kept as-is)
  test_runner.py              # Existing (kept as-is)
```

#### Harness Design

The harness is a Python unittest file that:

1. **Discovers** all registered language implementations (via a registry
   data structure, similar to the per-test repetition in the existing contract
   tests but DRY).
2. **Builds** each language's `ccc` binary if needed (same build steps as
   existing contract tests).
3. **Sets up** the mock binary as `opencode` on PATH (or via
   `CCC_REAL_OPENCODE`).
4. **Runs** a matrix of test cases × language implementations.
5. **Reports** failures with clear diff output showing which language
   diverged and on which dimension.

#### Language Registry

```python
LANGUAGES = [
    {
        "name": "Python",
        "build": None,  # no build needed
        "invoke": lambda prompt, env: ["python3", "python/call_coding_clis/cli.py", prompt],
        "env_extra": {"PYTHONPATH": "python"},
    },
    {
        "name": "Rust",
        "build": ["cargo", "build", "--bin", "ccc"],
        "invoke": lambda prompt, env: ["target/debug/ccc", prompt],
        "env_extra": {},
    },
    # ... etc for all 8 implemented languages
]
```

#### Test Cases

```python
TEST_CASES = [
    {
        "name": "happy_path",
        "prompt": "hello world",
        "expected_exit": 0,
        "expected_stdout": "mock: ok\n",
        "expected_stderr": "",
    },
    {
        "name": "exit_code_forwarding",
        "prompt": "exit 42",
        "expected_exit": 42,
        "expected_stdout": "",
        "expected_stderr": "mock: intentional failure\n",
    },
    {
        "name": "stderr_forwarding",
        "prompt": "stderr test",
        "expected_exit": 0,
        "expected_stdout": "mock: stdout output\n",
        "expected_stderr": "mock: stderr output\n",
    },
    {
        "name": "multiline_stdout",
        "prompt": "multiline",
        "expected_exit": 0,
        "expected_stdout": "line1\nline2\nline3\n",
        "expected_stderr": "",
    },
    {
        "name": "mixed_streams_nonzero",
        "prompt": "mixed streams",
        "expected_exit": 1,
        "expected_stdout": "mock: out\n",
        "expected_stderr": "mock: err\n",
    },
    {
        "name": "special_chars_in_prompt",
        "prompt": "fix the \"bug\" & edge-case",
        "expected_exit": 0,
        "expected_stdout": "mock: unknown prompt 'run fix the \"bug\" & edge-case'\n",
        "expected_stderr": "",
    },
]
```

Note: the mock receives the full argv that `ccc` constructs (e.g.,
`mock-coding-cli run "hello world"`), so the prompt table matches against
the full argument string after `run`.

### Implementation Steps

1. **Create `tests/mock-coding-cli/mock_coding_cli.sh`** — POSIX shell script
   implementing the prompt table. This is the simplest portable approach; no
   compilation needed.

2. **Create `tests/test_harness.py`** — Python unittest with:
   - Language registry with build + invoke lambdas
   - Test case registry with expected outputs
   - `setUpClass` that builds all language binaries once
   - Parameterized test methods using `subTest` for each language×case combo
   - Clear failure messages with language name, test case, and actual vs expected

3. **Validate** — Run against all 8 implemented languages, fix any behavioral
   differences the harness reveals.

4. **Integrate** — Add to CI alongside existing contract tests. Existing tests
   remain as the "basic smoke test" layer; the harness adds depth.

### Why a Mock Instead of the Real `opencode`

- **Determinism** — Real `opencode` makes network calls, has latency, may
  produce variable output. The mock is 100% deterministic.
- **Speed** — No network, no model inference. Tests run in milliseconds.
- **Coverage** — We can test edge cases (exit codes, large output, special
   chars) that would be impossible or expensive with a real CLI.
- **Isolation** — We're testing the *wrapper* behavior, not the underlying
  CLI. The mock lets us focus on the wrapper contract.

### Acceptance Criteria

- [ ] Mock binary exists and passes its own self-test
- [ ] Harness discovers and tests all 8 implemented languages
- [ ] At least 6 test cases covering: happy path, exit code forwarding,
      stderr forwarding, multiline output, mixed streams, special characters
- [ ] All currently-passing implementations pass all test cases
- [ ] Any behavioral differences found are either fixed or documented as
      known divergences in `IMPLEMENTATION_REFERENCE.md`
- [ ] `review-and-fix` skill run on the completed harness

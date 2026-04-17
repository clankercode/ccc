# `--timeout-secs` — design

## Goal

Add a new CLI flag `--timeout-secs <N>` to `ccc`. When supplied, `ccc` must
terminate the wrapped runner subprocess after `N` seconds and exit, even if
the runner has not finished. The feature ships in Python and Rust (required
implementations per `ADDING_FEATURES.md`); broader language rollout is
deferred.

## User-facing behavior

- Flag: `--timeout-secs <N>` where `N` is a positive integer number of seconds.
- Order-independent pre-prompt control token (like `--yolo`, `--permission-mode`).
- Validation is performed at parse time. `--timeout-secs` with a missing,
  non-integer, zero, or negative value causes `parse_args` to raise
  `ValueError` in Python and to set a public sentinel in Rust that
  `resolve_command` converts into an `Err` with the same message. The exact
  error message is:
  `--timeout-secs must be a positive integer`
  Exit code on this error: 1 (existing CLI convention for bad args).
- On timeout, `ccc`:
  1. Sends SIGKILL directly. We do not send SIGTERM first. Rationale: keeps
     Python and Rust identical without adding a Rust dependency for
     `libc::kill(SIGTERM)`, and a user who asked for a timeout usually wants
     the process gone, not politely nudged. Any partial stdout/stderr that
     was already pumped through our read threads is preserved; nothing new
     will appear after SIGKILL.
  2. Emits a single stderr warning line:
     `warning: timed out after <N> seconds; killed runner`
  3. Returns exit code **124** (GNU `timeout(1)` convention). This overrides
     whatever signal code the subprocess would otherwise have returned.
- Partial output captured up to the kill is preserved. Run artifacts
  (transcript / output log) are finalized normally with whatever was
  received. The footer (`>> ccc:output-log >> ...`) prints **after** the
  timeout warning and **before** `main` returns, so stderr ordering is
  `warning → footer → exit(124)`. The cross-impl contract test asserts this
  ordering.
- The timeout is enforced by the `ccc` wrapper itself. No runner-specific
  flag translation.
- Alias / config support: out of scope for this change. CLI-only. Adding it
  to `AliasDef` / `CccConfig` is a trivial follow-up that can ship later.

## Architecture

### Python

- `parser.ParsedArgs`: new field `timeout_secs: int | None = None`.
- `parser.parse_args`: recognize `--timeout-secs <N>`. Parse the integer
  immediately; if missing / non-integer / `<= 0`, raise
  `ValueError("--timeout-secs must be a positive integer")` directly from
  `parse_args`. This matches the reviewer's SHOULD-FIX #4 and removes the
  sentinel dance. `cli.main` already has a `try/except ValueError` block
  around `resolve_command`; move it (or add a second block) so that parse
  errors also return 1 with the message on stderr.

- `runner.CommandSpec`: new field `timeout_secs: int | None = None`.

- `runner.CompletedRun`: new field `timed_out: bool = False`.
  - Downstream library users comparing by field are unaffected because
    Python dataclasses with defaults remain construction-compatible.

- `runner.Runner`: single timeout implementation shared by `run` and `stream`.
  When `spec.timeout_secs is not None`:
  - `run` internally delegates to `stream` with a no-op callback. This
    removes the injected-executor edge case raised by reviewer MUST-FIX #1:
    the injected `executor` is simply not called when a timeout is set, and
    we document that on the `Runner` docstring. (Tests that inject
    `executor` don't set `timeout_secs`, so no test breaks.)
  - `stream` already uses Popen. Add a watchdog thread that sleeps `N`
    seconds, then — **before** calling `process.kill()` — sets
    `timed_out_event.set()`. This ordering fixes reviewer MUST-FIX #3
    (visibility): any observer that sees the child reaped will see the flag
    set because the flag is stored before the signal is delivered. The
    main thread also joins the watchdog thread before returning, so the
    flag is always consistent by the time `CompletedRun` is constructed.
  - The watchdog checks `process.poll()` before killing; if the process
    already exited on its own, the watchdog exits without action.
  - stdin is fully written before the watchdog starts (existing code
    already does this at the top of `_default_stream_executor`).

- `cli.main`: after building `spec`, copy `parsed.timeout_secs` into
  `spec.timeout_secs` across every branch (text, json, stream-text,
  stream-json, formatted, stream-formatted). Instead of copy-pasting, do
  this once immediately after `spec = CommandSpec(...)` is constructed.
  On return, if `result.timed_out` is true, print the warning to stderr,
  then still run artifact finalization and the footer, then `return 124`.

### Rust

- `parser::ParsedArgs`: new field `pub timeout_secs: Option<u64>`.
- `parser::parse_args` recognises `--timeout-secs <N>`. Because the function
  currently returns `ParsedArgs` (not `Result`), the public API stays
  unchanged: on bad input, set `timeout_secs = Some(0)` as a sentinel and
  let `resolve_command` return the canonical error string. This is the
  Rust-side of reviewer SHOULD-FIX #4 — we keep the error deferred to
  `resolve_command` because changing `parse_args`'s signature to `Result`
  would be a much bigger API change. Missing value (no token after
  `--timeout-secs`) also sets `Some(0)`.
- `resolve_command`: when `parsed.timeout_secs == Some(0)`, return
  `Err("--timeout-secs must be a positive integer".to_string())`.
- `exec::CommandSpec`: new field `pub timeout_secs: Option<u64>`. Gate the
  struct with `#[non_exhaustive]` (reviewer MUST-FIX #2) so future fields
  don't keep forcing minor bumps; note the breaking change for 0.3.0 in
  CHANGELOG. Provide a builder method `with_timeout_secs(mut self, secs:
  u64) -> Self` for ergonomic construction.
- `exec::CompletedRun`: new field `pub timed_out: bool`. Same
  `#[non_exhaustive]` treatment. Update `Runner::run` and `Runner::stream`
  constructions to populate it.
- `exec::Runner::run` (`default_run_executor`): when `spec.timeout_secs`
  is `Some(n)`, spawn via `Command::spawn()` instead of `.output()`, then
  run the watchdog below before collecting output.
- `exec::Runner::stream` (`default_stream_executor`): add a watchdog thread
  (reviewer SHOULD-FIX #5): it sleeps `n` seconds, checks `child.try_wait()`,
  and if the child is still alive, stores `timed_out.store(true,
  Ordering::SeqCst)` FIRST, then calls `child.kill()`. We use
  `std::process::Child::kill()` (SIGKILL on unix, TerminateProcess on
  Windows) — no new dependency required. Grace period dropped to keep both
  impls simple and identical. `Runner::stream` joins the watchdog thread
  before constructing `CompletedRun`.
- `bin/ccc.rs`: propagate `parsed.timeout_secs` to `spec.timeout_secs`; on
  `result.timed_out`, print the warning to stderr, then handle artifacts,
  then `std::process::exit(124)`.

### Cross-language contract

- Parser contract: `--timeout-secs <N>` is accepted. Validation errors use
  the exact message `--timeout-secs must be a positive integer` and exit
  code 1. Error hits stderr and nothing on stdout.
- Runtime contract: when the wrapped binary sleeps longer than `N`,
  `ccc` exits 124 and stderr contains `timed out after <N> seconds`.
  Stderr ordering: `warning` line first, footer line (if enabled) second.

## Flag position and prompt handling

Parsed like `--save-session`: recognized only before the prompt positional
starts; `--` shifts everything after into prompt text (existing invariant).

## Interactions

- `--output-log-path` footer: still emitted under timeout. Order is warning
  → footer → exit(124).
- `--cleanup-session` after a timeout: still attempt cleanup using whatever
  session id we extracted from partial stdout/stderr. If nothing was
  extracted, the existing "could not find ... session ID for cleanup"
  warning fires. No change to cleanup code.
- `--save-session` is orthogonal.

## Error handling

- Timeout → exit 124. Single source of truth. We do not propagate the
  SIGKILLed child's native exit status.
- If the child exits on its own with a non-zero code before the timeout
  fires, we forward that code unchanged (current behavior).
- Invalid `--timeout-secs` argument → exit 1 with the canonical message on
  stderr.

## Help text

Exact one-line entry added to both `HELP_TEXT` blocks (Python in
`call_coding_clis/help.py`, Rust in `rust/src/help.rs`), in the "Flags"
section below `--forward-unknown-json`:

```
  --timeout-secs <N>                    Kill the runner after N seconds and exit 124
```

Both implementations ship the exact same line so the cross-impl contract
test can assert equality.

## Testing

### Python unit (`tests/test_parser_config.py`)

- `parse_args(["--timeout-secs", "30", "hi"])` returns `timeout_secs=30`.
- `parse_args(["--timeout-secs", "abc", "hi"])` raises
  `ValueError("--timeout-secs must be a positive integer")`.
- `parse_args(["--timeout-secs", "0", "hi"])` raises the same error.
- `parse_args(["--timeout-secs"])` raises the same error (no value).

### Rust unit (`rust/tests/parser_tests.rs`)

- `parse_args` with valid value sets `timeout_secs == Some(30)`.
- `parse_args` with bad value sets `timeout_secs == Some(0)` and
  `resolve_command` returns `Err("--timeout-secs must be a positive integer")`.
- Missing value → `Some(0)` → same error.

### Python runner unit (`tests/test_runner.py`)

- Add a test that constructs `CommandSpec(argv=["/bin/sh", "-c", "sleep 5"],
  timeout_secs=1)`, calls `Runner().run(spec)`, and asserts:
  - `result.timed_out is True`
  - Elapsed wall time under 3 seconds.
- Gate with `@unittest.skipUnless(sys.platform != "win32", ...)`.

### Rust runner unit (`rust/tests/library_api_tests.rs`)

- Parallel test to the Python one, `#[cfg(unix)]`.

### Cross-impl contract (`tests/test_ccc_contract_impl.py`)

- Help text contains `--timeout-secs <N>` line; exact match asserted.
- `ccc --timeout-secs 0 hi` returns non-zero and stderr contains
  `--timeout-secs must be a positive integer`.
- `ccc --timeout-secs abc hi` returns non-zero and same message.

### Cross-impl harness (`tests/test_harness.py`)

- Extend `mock_coding_cli.sh` with a `sleep N` prompt branch:
  `case "$PROMPT" in sleep\ *) exec sleep "${PROMPT#sleep }";; esac`.
  Placed alongside the existing prompt table so the style matches.
- Add a test that invokes `ccc --timeout-secs 1 "sleep 5"` via the Python
  and Rust binaries with the mock wired as `CCC_REAL_OPENCODE`, and
  asserts:
  - exit code 124
  - stderr contains `timed out after 1 seconds`
  - stderr order: warning before footer
  - wall time under 4 seconds
- The test is opt-in to `Python` and `Rust` in the same way
  `OUTPUT_LOG_PATH_IMPLEMENTATIONS` scopes its tests.

## Documentation

- `README.md`: add `--timeout-secs` entry to the flags list.
- `python/README.md`, `rust/README.md`: mirror the entry.
- `docs/llms.txt`: add to the flags list if that file enumerates flags.
- `docs/index.html`: add a short entry if that file enumerates flags.
- `SHARED_CHANGES.md`: new dated entry for 2026-04-18:
  - what changed
  - docs updated
  - rollout = Python + Rust only
  - shared tests updated: `tests/test_parser_config.py`,
    `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`,
    `tests/test_runner.py`, `rust/tests/parser_tests.rs`,
    `rust/tests/library_api_tests.rs`, `tests/mock-coding-cli/mock_coding_cli.sh`
- CHANGELOG.md: move from `## Unreleased` → `## 0.3.0 - 2026-04-18`, list
  the feature and the `CompletedRun` / `CommandSpec` field additions +
  `#[non_exhaustive]` marker (noting the tiny crate-level breaking change).

## Version bump

- `VERSION`: `0.2.0` → `0.3.0`.
- `rust/Cargo.toml` (and regenerated `Cargo.lock`): `version = "0.3.0"`.
- Repo-root `Cargo.toml`: confirm if it tracks a version; currently it
  only references the rust subcrate, so likely no change needed.

## Implementation order

1. Python parser + validation + parser unit tests.
2. Python `CommandSpec` / `CompletedRun` / `Runner` changes + runner unit
   test (slow-sh).
3. Python CLI wiring + stderr warning + exit 124 + print_help entry.
4. Rust parser + tests.
5. Rust `CommandSpec` / `CompletedRun` / `Runner` changes + unit test.
6. Rust CLI wiring + warning + exit 124 + HELP_TEXT entry.
7. Add `sleep` branch to `mock_coding_cli.sh`.
8. Cross-impl contract test updates.
9. Cross-impl harness test updates.
10. Docs + `SHARED_CHANGES.md` + CHANGELOG + VERSION + Cargo.toml.
11. Run targeted tests:
    - `PYTHONPATH=python python3 -m unittest tests.test_parser_config -v`
    - `PYTHONPATH=python python3 -m unittest tests.test_runner -v`
    - `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Python -v`
    - `cd rust && cargo test -j1`
    - `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v`
    - `PYTHONPATH=. python3 tests/test_harness.py Python -v`
    - `PYTHONPATH=. python3 tests/test_harness.py Rust -v`
12. `just install-rs`.
13. Commit.
14. Run `review-and-fix` skill and address findings.

## Open questions (answered)

- **Grace period?** None. SIGKILL-only on both impls for uniformity and to
  avoid a Rust dep. A user asking for a hard timeout is asking for a hard
  kill.
- **Why 124?** GNU `timeout(1)` convention; no existing ccc exit-code
  conflict.
- **Why wrapper-enforced?** Uniform behavior across runners; many runners
  have no timeout flag.

--- SUMMARY ---

- Adds `--timeout-secs <N>` to `ccc`: order-independent, positive integer seconds
- On timeout: SIGKILL the runner (no grace), exit 124, stderr warning `timed out after <N> seconds; killed runner`, then footer (order tested)
- Python + Rust only; other languages deferred
- Invalid value: parse-time `ValueError` in Python, deferred `Err` from `resolve_command` in Rust, exact message `--timeout-secs must be a positive integer`, exit 1
- `CommandSpec` and `CompletedRun` gain `timeout_secs` / `timed_out` fields; Rust structs marked `#[non_exhaustive]` so future field additions don't force further semver breaks
- Watchdog sets `timed_out` flag BEFORE sending SIGKILL and is joined before `CompletedRun` is constructed, so visibility is race-free
- `Runner::run` in Python delegates to `stream` when a timeout is set, giving a single watchdog implementation
- Tests: parser unit (both langs), runner unit with real `/bin/sh -c 'sleep 5'` (both langs, unix-gated), cross-impl contract for help text + error messages, cross-impl harness with a new `sleep N` mock branch asserting exit code, stderr content, and wall time
- Docs: README files, docs/llms.txt, docs/index.html (if applicable), SHARED_CHANGES.md entry, CHANGELOG
- Version bump: 0.2.0 → 0.3.0 (VERSION + rust/Cargo.toml)
- After commit: run `review-and-fix` skill to validate the landed change

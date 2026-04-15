# CCC Run Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stable per-run artifact directory for `ccc` runs that stores `output.txt`, the user-visible transcript, and a parseable footer line for scripts.

**Architecture:** Put the filesystem logic behind small helper modules in the Python and Rust implementations, then wire those helpers into the existing output-mode branches. The CLI should tee the exact stdout stream it emits into the transcript file, derive `output.txt` from the structured parser when structured output is available, and print one footer line on stderr unless the caller suppresses it.

This plan only changes Python and Rust for v1. The other language ports stay unchanged until a later rollout so the shared contract can settle on the final behavior first.

**Tech Stack:** Python 3.11+, Rust, `unittest`, `cargo test`, the existing parser and JSON-output modules, and the repo's targeted `test_impl.sh` checks.

---

### Task 1: Python Run-Artifacts Plumbing

**Files:**
- Create: `python/call_coding_clis/artifacts.py`
- Modify: `python/call_coding_clis/json_output.py`
- Modify: `python/call_coding_clis/parser.py`
- Modify: `python/call_coding_clis/help.py`
- Modify: `python/call_coding_clis/cli.py`
- Create: `tests/test_run_artifacts.py`

- [ ] **Step 1: Write the failing tests**
  - Add unit tests that lock down these behaviors:
    - state-root resolution chooses `XDG_STATE_HOME`, `~/Library/Application Support`, or `%LOCALAPPDATA%` correctly
    - run-id creation retries when the first candidate directory already exists
    - `output.txt` is written alongside exactly one transcript file
    - `stream-formatted` transcripts capture the rendered human chunks that the CLI prints, not raw JSON event lines
    - `text` requests that are upgraded into structured OpenCode streaming still write `transcript.txt`
    - `--no-output-log-path` suppresses only the footer line
    - the footer is the last stderr line after cleanup warnings
    - a directory-creation failure skips the footer
    - a post-directory file-write failure still leaves the other artifact and still prints the footer
  - Run `PYTHONPATH=python python3 -m unittest tests.test_run_artifacts -v` and expect failures.

- [ ] **Step 2: Implement the minimal Python changes**
  - `artifacts.py` should own the testable path helpers and a small `RunArtifactWriter` that:
    - resolves the platform state root
    - creates `ccc/runs/<client>-<run-id>` with retry
    - opens either `transcript.txt` or `transcript.jsonl`
    - appends the exact stdout text the CLI emits
    - writes `output.txt`
    - formats the footer as `>> ccc:output-log >> <absolute run dir>`
  - `json_output.py` should expose the structured output object from `StructuredStreamProcessor` so the CLI can read `final_text` after streaming finishes.
  - `parser.py` should accept `--output-log-path` and `--no-output-log-path` as a boolean pair with last-one-wins parsing.
  - `help.py` should mention the new footer flags in the run-controls help text.
  - `cli.py` should:
    - create the artifact writer after output mode resolution
    - tee the live stdout-rendering path into the transcript writer
    - write `output.txt` from `ParsedJsonOutput.final_text` for structured modes, including the OpenCode visible-work upgrade path
    - fall back to sanitized stdout for plain `text` and `stream-text`
    - print the footer on stderr last when enabled

- [ ] **Step 3: Re-run Python verification**
  - Run `PYTHONPATH=python python3 -m unittest tests.test_run_artifacts -v`
  - Run `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Python -v`
  - Run `./test_impl.sh python`

- [ ] **Step 4: Commit**
  - Commit the Python implementation and its tests once the verification passes.

### Task 2: Rust Run-Artifacts Plumbing

**Files:**
- Create: `rust/src/artifacts.rs`
- Modify: `rust/src/lib.rs`
- Modify: `rust/src/json_output.rs`
- Modify: `rust/src/parser.rs`
- Modify: `rust/src/help.rs`
- Modify: `rust/src/bin/ccc.rs`
- Create: `rust/tests/run_artifacts_tests.rs`

- [ ] **Step 1: Write the failing tests**
  - Add Rust tests that cover the same contract as the Python side:
    - platform state-root resolution
    - run-id retry behavior
    - footer formatting and suppression
    - `output.txt` plus exactly one transcript file
    - `stream-formatted` transcript capture from rendered chunks
    - the OpenCode text-upgrade path still using `transcript.txt`
    - the footer is the last stderr line after cleanup warnings
    - directory-creation failure skipping the footer
    - post-directory file-write failure leaving the footer intact
  - Run `cd rust && cargo test` and expect failures in the new artifact tests.

- [ ] **Step 2: Implement the minimal Rust changes**
  - `artifacts.rs` should own the platform path resolver, unique run directory creation, transcript/output file writing, and footer formatting.
  - `json_output.rs` should expose the structured stream processor's parsed output so the CLI can read `final_text` after streaming finishes.
  - `parser.rs` should parse `--output-log-path` and `--no-output-log-path` into a boolean field without introducing a config key.
  - `help.rs` should advertise the new footer flags in the run help text.
  - `bin/ccc.rs` should:
    - create the artifact writer once the output plan is known
    - tee the exact stdout that is printed into the transcript writer
    - write `output.txt` from structured `final_text` whenever the effective mode is structured
    - keep plain text modes on sanitized stdout fallback
    - print the footer last when enabled

- [ ] **Step 3: Re-run Rust verification**
  - Run `cd rust && cargo test`
  - Run `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v`
  - Run `just install-rs`
  - Run `./test_impl.sh rust`

- [ ] **Step 4: Commit**
  - Commit the Rust implementation and its tests once the verification passes.

### Task 3: Shared Harness and Contract Coverage

**Files:**
- Modify: `tests/test_harness.py`
- Modify: `tests/test_ccc_contract_impl.py`
- Modify: `tests/test_ccc_contract.py`

- [ ] **Step 1: Make the harness footer-aware**
  - Add a keyword-only `include_output_log_path: bool = False` parameter to `LanguageSpec.invoke`, `invoke_extra`, and `invoke_with_args`.
  - When that parameter is `False`, append `--no-output-log-path` before the prompt so the existing contract suite keeps its current stderr expectations.
  - When that parameter is `True`, leave the footer enabled so the new artifact tests can assert the parseable footer line.

- [ ] **Step 2: Add explicit contract tests for the new behavior**
  - Add end-to-end assertions in `tests/test_ccc_contract_impl.py` that:
    - verify the footer line on Python and Rust `ccc` runs when footer output is enabled
    - parse the footer path and confirm the artifact directory exists
    - confirm `output.txt` is present
    - confirm `transcript.txt` is used for text and formatted streams
    - confirm `transcript.jsonl` is used for JSON-oriented streams
    - confirm `--no-output-log-path` suppresses the footer while leaving the files on disk
    - confirm the footer is emitted after cleanup warnings
    - leave `help`, `config`, and `add` flows unchanged
  - Keep `tests/test_ccc_contract.py` as the compatibility wrapper unless the selected-language logic needs a small adjustment.

- [ ] **Step 3: Re-run the cross-implementation checks**
  - Run `./test_impl.sh python`
  - Run `./test_impl.sh rust`

- [ ] **Step 4: Commit**
  - Commit the shared harness and contract updates once the checks pass.

### Task 4: Docs and Shared Change Log

**Files:**
- Modify: `README.md`
- Modify: `docs/clis/README.md`
- Modify: `docs/clis/output-mode-compatibility.md`
- Modify: `docs/llms.txt`
- Modify: `SHARED_CHANGES.md`

- [ ] **Step 1: Update the docs**
  - Document the footer line format and the fact that it is parseable from stderr.
  - Document the per-run artifact directory layout and the file split between `output.txt`, `transcript.txt`, and `transcript.jsonl`.
  - Document that `text` requests upgraded into structured streaming still use `transcript.txt`.

- [ ] **Step 2: Record the shared rollout**
  - Add a dated `SHARED_CHANGES.md` entry that says:
    - Python and Rust now ship the new artifact/footer behavior
    - the docs were updated
    - the shared tests were updated
    - the remaining HTTP/HTTPS sink work stays deferred in `TASKS.md`

- [ ] **Step 3: Final verification**
  - Re-run `./test_impl.sh python`
  - Re-run `./test_impl.sh rust`
  - Confirm `just install-rs` still points the local `ccc` at the tested Rust build
  - Run one direct Python smoke against the mock runner and a temporary `XDG_STATE_HOME`:
    ```bash
    env PYTHONPATH=python MOCK_JSON_SCHEMA=opencode \
      CCC_REAL_OPENCODE=tests/mock-coding-cli/mock_coding_cli.sh \
      XDG_STATE_HOME="$(mktemp -d)" \
      python3 python/call_coding_clis/cli.py oc ..fmt "tool call"
    ```
  - Run one direct Rust smoke against the same mock runner and a temporary `XDG_STATE_HOME`:
    ```bash
    env MOCK_JSON_SCHEMA=opencode \
      CCC_REAL_OPENCODE=tests/mock-coding-cli/mock_coding_cli.sh \
      XDG_STATE_HOME="$(mktemp -d)" \
      rust/target/debug/ccc oc ..fmt "tool call"
    ```
  - In both smokes, confirm stderr ends with `>> ccc:output-log >> ...` and the run directory contains `output.txt` plus the correct transcript file, with the folder name prefixed by the canonical client type.

- [ ] **Step 4: Commit**
  - Commit the docs and changelog updates after verification passes.

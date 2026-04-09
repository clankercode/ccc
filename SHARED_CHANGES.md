# Shared Changes

This file records shared `ccc` features, fixes, and semantic changes.

Use it when:
- a change affects the shared CLI contract
- a change affects parser/config/help semantics expected across implementations
- a change affects runner execution behavior, stdin/env behavior, or shared test expectations

Entry format:

```md
## YYYY-MM-DD

### Short change title
- Change: short description of the semantic change
- Required implementations: Python and Rust
- Additional rollout: deferred | rolled out to <languages>
- Shared tests updated: <tests>
- Notes: optional short context
```

## 2026-04-10

### Project-local config files are now discovered in Python and Rust
- Change: Python and Rust now search upward from the current directory for a project-local `.ccc.toml` and merge it with the global config chain, with local values overriding XDG and home defaults
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`, `rust/src/config.rs`, `rust/tests/help_tests.rs`
- Notes: `README.md`, `docs/llms.txt`, `docs/index.html`, `python/call_coding_clis/help.py`, `rust/src/help.rs`, and `CCC_PARSER_CONFIG_DESIGN.md` now describe the project-local file and the XDG/home fallback chain

### Preset prompts now fall back in Python and Rust
- Change: Python and Rust now parse `aliases.<name>.prompt` and let `@name` fall back to that preset prompt when explicit user prompt text is missing or whitespace-only; explicit prompt text still overrides the preset prompt when present
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `INDEX_MASTER_SPEC.md`, `CCC_PARSER_CONFIG_DESIGN.md`, `docs/llms.txt`, and the Python/Rust help text; `TASKS.md` backlog item removed

## 2026-04-10

### Shared real-runner overrides now cover Claude and Kimi too
- Change: Python and Rust now support `CCC_REAL_CLAUDE` and `CCC_REAL_KIMI` alongside `CCC_REAL_OPENCODE`, and the docs now include a maintained mock-smoke recipe for exercising formatted output without PATH symlink setup
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_runner.py`, `rust/tests/help_tests.rs`
- Notes: this follow-up closes the local debugging gap discovered while validating OSC sanitization; ad hoc mock smoke runs can now point `ccc` at a mock Claude or Kimi binary directly through env overrides

## 2026-04-09

### Human-facing OSC sanitization is configurable in Python and Rust
- Change: Python and Rust add `--sanitize-osc` / `--no-sanitize-osc` plus config and alias support for stripping disruptive OSC output from human-facing rendering while preserving OSC 8 hyperlinks
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_harness.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`, `rust/tests/help_tests.rs`
- Notes: formatted modes default to OSC sanitization on; raw machine modes stay unchanged except for the existing always-on OpenCode raw-output cleanup that keeps `oc json` machine-clean

### Output modes and formatted streaming added to Python and Rust
- Change: Python and Rust now support `--output-mode`, dot-sugar output selectors, raw streaming, and formatted transcript rendering with shared output-mode semantics
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`, `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_json_output.py`, `rust/tests/parser_tests.rs`, `rust/tests/help_tests.rs`, `rust/tests/json_output_tests.rs`, `rust/tests/config_tests.rs`
- Notes: default output mode is now configurable in TOML; real sanitized runner transcript fixtures were added under `tests/fixtures/runner-transcripts/`; local smoke verification confirmed Claude `stream-json` needs `--verbose` and OpenCode uses `--format json`; Python and Rust now add Claude `--verbose` automatically for `stream-json` and `stream-formatted`; `.fmt` and `..fmt` now have explicit contract/runtime coverage; follow-up work in progress adds `--forward-unknown-json` so formatted modes can surface unhandled structured events during integration/debugging; Python and Rust also suppress duplicate final assistant/result renders when Claude streams `text_delta` chunks and then repeats the same full text in later `assistant`/`result` events; the manual visual smoke script lives under `scripts/smoke-output-modes.sh`, now defaults Claude smoke runs to `:anthropic:claude-haiku-4-5`, and no longer enables unknown-JSON forwarding by default

### Claude unknown stream-event fixture added for cross-language parsers
- Change: a real Claude `stream_unknown_events` fixture now captures unhandled stream-event shapes like `message_start`, `message_delta`, `message_stop`, `signature_delta`, and `rate_limit_event`
- Required implementations: Python and Rust
- Additional rollout: test-only parser fixture coverage added in TypeScript, Ruby, Perl, Crystal, and Elixir
- Shared tests updated: `tests/test_json_output.py`, `rust/tests/json_output_tests.rs`, `typescript/tests/json_output.test.mjs`, `ruby/test/test_json_output.rb`, `perl/t/06_json_output.t`, `crystal/spec/json_output_spec.cr`, `elixir/test/call_coding_clis/json_output_test.exs`
- Notes: this was a test rollout, not a feature rollout for those extra languages; they currently pin the fixture through `raw_lines` rather than `unknown_json_lines`; languages without raw/unknown line retention still need follow-up work if we want the same regression signal there

### Kimi human-mode stderr filtering and current OpenCode JSON event shape
- Change: Python and Rust now strip Kimi's `To resume this session: kimi -r ...` stderr hint in human-facing formatted modes, and the OpenCode JSON parser now understands the current event-stream style `step_start` / `text` / `step_finish` output instead of assuming only a legacy one-shot `response` object
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_runner.py`, `tests/test_json_output.py`, `rust/tests/json_output_tests.rs`
- Notes: this follow-up came from real smoke runs; OpenCode `--format json` currently emits event objects rather than the older one-shot response shape, and Python/Rust now also strip OpenCode OSC terminal-title sequences from buffered raw output so `oc json` stays machine-clean in local verification

### Model thinking capability data is now structured
- Change: model-level thinking capability notes now live in `docs/clis/model-capabilities.json`, with refresh instructions in `docs/clis/updating-model-capabilities.md`
- Required implementations: none
- Additional rollout: docs-only
- Shared tests updated: none
- Notes: `docs/clis/README.md` now treats the markdown thinking matrix as a human summary rather than the source of truth; the JSON now distinguishes raw auth-scoped `runner_discoveries` from normalized `models`, and the OpenCode inventory was seeded from a successful outside-sandbox `opencode models` run

## 2026-04-09

### Thinking-level mapping clarified
- Change: `+3` resolves to `high` and `+4` resolves to the vendor top tier; Anthropic uses `max` and OpenAI-style labels use `xhigh`
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `rust/tests/parser_tests.rs`
- Notes: added a thinking matrix under `docs/clis/README.md` and corrected the stale mapping note in `CCC_PARSER_CONFIG_DESIGN.md`

## 2026-04-09

### Permission mode added to Python and Rust
- Change: Python and Rust now support `--permission-mode <safe|auto|yolo|plan>` with runner-specific mappings where the semantics are honest
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `tests/test_runner.py`, `rust/tests/parser_tests.rs`, `rust/tests/help_tests.rs`
- Notes: `--yolo` remains supported as syntax sugar for `--permission-mode yolo`; current mappings are partial by runner and unsupported modes warn instead of guessing

### Yolo mode and free-order controls added to Python and Rust
- Change: Python and Rust now support `--yolo` / `-y`, free-order pre-prompt control tokens, and `--` to force literal prompt text
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `tests/test_runner.py`, `rust/tests/parser_tests.rs`, `rust/tests/help_tests.rs`
- Notes: bare `!!` was rejected because shell history expansion makes it unsafe; Claude now uses `claude -p`, Crush uses `crush run`, OpenCode yolo is env-config based, and RooCode yolo remains unverified

### Codex runner now uses `codex exec`
- Change: Codex runner now uses `codex exec` for non-interactive execution instead of bare `codex`
- Required implementations: Python and Rust
- Additional rollout: rolled out to C, C++, Go, TypeScript, Perl, PHP, Ruby, Crystal, D, Elixir, F#, Haskell, Nim, OCaml parser/tests, PureScript, Zig
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`
- Notes: ASM remains on the first-pass prompt-only contract path

### Visible-thinking flag added to Python and Rust
- Change: `--show-thinking` / `--no-show-thinking` added to Python and Rust with config-backed `show_thinking` defaulting off
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `tests/test_runner.py`, `rust/tests/parser_tests.rs`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: visible-thinking support is runner-specific and not yet rolled out to the other language implementations

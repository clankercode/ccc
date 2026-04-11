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

## 2026-04-12

### Thinking is visible by default with low effort
- Change: Python and Rust now default `show_thinking` to on and default `thinking` to level `1`; OpenCode receives `--thinking` by default, Claude receives `--thinking enabled --effort low`, and Kimi receives `--thinking`
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `rust/tests/parser_tests.rs`, `tests/test_ccc_contract_impl.py`
- Notes: `--no-show-thinking` still disables OpenCode visible-thinking output, while explicit `+0` / `+none` still disables runner thinking where supported

### `ccc add` success output now uses a checkmarked footer
- Change: Python and Rust now print successful alias writes as a checkmarked heading followed by an indented alias block, matching the wizard menu layout
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_runner.py`, `rust/tests/help_tests.rs`
- Notes: updated `docs/clis/README.md`

### `ccc add` wizard menus now use color on TTYs
- Change: Python and Rust now color-code bounded-choice `ccc add` wizard menus while preserving plain output for pipes; `FORCE_COLOR` enables menu color and `NO_COLOR` disables it, matching the existing formatted-output color policy
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_runner.py`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, and `docs/clis/README.md`

## 2026-04-11

### `ccc add` alias wizard added in Python and Rust
- Change: Python and Rust now support `ccc add [-g] <alias>` to write `[aliases.<name>]` entries through a line-prompt wizard or non-interactively with alias flags plus `--yes`; normal mode writes the resolved config path and falls back to a new global config when none exists, while `-g` forces the effective global config
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, `docs/clis/README.md`, and Python/Rust help text; the generated config schema is unchanged because the wizard writes existing alias keys

### Session persistence controls added in Python and Rust
- Change: Python and Rust now default to non-persistent runner modes where upstream CLIs support them, adding Claude `--no-session-persistence` and Codex `--ephemeral`; runners without verified no-persist flags warn by default, `--save-session` explicitly allows saved sessions, and `--cleanup-session` tries safe post-run cleanup for OpenCode and Kimi
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`, `tests/mock-coding-cli/mock_coding_cli.sh`, `rust/tests/parser_tests.rs`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, `docs/clis/README.md`, and runner docs under `docs/clis/`; Crush and RooCode cleanup intentionally warn instead of deleting guessed sessions

## 2026-04-10

### Alias `prompt_mode` added in Python and Rust
- Change: Python and Rust now support `[aliases.<name>].prompt_mode = "default"|"prepend"|"append"` alongside alias `prompt`; `default` preserves preset-prompt fallback behavior, while `prepend` and `append` require an explicit prompt argument and compose alias prompt text with the user prompt using a single newline
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`, `rust/tests/config_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, the Python/Rust help text, the canonical config example fixture, and removed the completed backlog item from `TASKS.md`

### `ccc config` now prints the resolved config file in Python and Rust
- Change: Python and Rust now support `ccc config`, which prints the resolved config file path plus that file's raw contents; `CCC_CONFIG` wins when it points at an existing file, otherwise the command falls back to the project-local `.ccc.toml`, then `XDG_CONFIG_HOME/ccc/config.toml`, then `~/.config/ccc/config.toml`, and exits non-zero with a helpful error if nothing is found
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, the Python/Rust help text, and removed the completed backlog item from `TASKS.md`

### Help flags now win anywhere in argv in Python and Rust
- Change: Python and Rust now treat a standalone `-h` or `--help` token as an immediate help request anywhere in argv, so `ccc @reviewer --help`, `ccc "prompt" --help`, and `ccc -- --help` all print help instead of being parsed as prompt text or normal controls
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, and the Python/Rust help text; removed the completed backlog item from `TASKS.md`

### Runner version discovery now prefers install metadata in Python and Rust
- Change: Python and Rust now read trusted install metadata for OpenCode, Codex, Kimi, and Claude when rendering the help runner checklist, and only fall back to spawning `<runner> --version` when that direct lookup is unavailable
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_runner.py`, `tests/test_ccc_contract_impl.py`, `rust/src/help.rs`, `rust/tests/help_tests.rs`
- Notes: OpenCode and Codex use package metadata, Kimi uses Python dist-info metadata, Claude uses the versioned local install path, and Crush/RooCode remain on command fallback; removed the completed backlog item from `TASKS.md`

### OpenCode structured streaming now supports both `stream-formatted` and `stream-json` in Python and Rust
- Change: Python and Rust now treat OpenCode `--format json` as a live JSON-event stream, so both `oc ..fmt` and `oc ..json` are supported alongside `oc .fmt` and `oc .json`, using the same upstream event stream rather than a separate NDJSON mode selector
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_harness.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`
- Notes: updated `docs/clis/output-mode-compatibility.md` and `docs/clis/json-event-references.md`; the original `oc ..fmt` rollout left the OpenCode capability gate too narrow, and this follow-up aligns the parser contract with the existing `--format json` event-stream implementation in both languages

### Canonical controls help text now matches across all `ccc` implementations
- Change: the shared help/usage banner now uses `ccc [controls...] "<Prompt>"` and the core controls section now carries two exhaustive shared examples across the language implementations
- Required implementations: Python and Rust
- Additional rollout: rolled out to C, C++, TypeScript, Go, Ruby, Perl, D, Nim, F#, Haskell, OCaml, Crystal, PHP, PureScript, Elixir, Zig, and x86-64 ASM
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `go/help_test.go`, `typescript/tests/help.test.mjs`, `nim/tests/test_help.nim`, `purescript/test/Main.purs`, `ocaml/test/test_help.ml`, `crystal/spec/help_spec.cr`, `zig/tests/help_test.zig`
- Notes: updated `docs/clis/README.md`, `docs/llms.txt`, `docs/index.html`, and `_dispatch_help.sh`; removed the backlog item from `TASKS.md`

### Permission-mode mappings were narrowed to honest upstream controls in Python and Rust
- Change: Python and Rust now treat `--permission-mode safe` as an explicit OpenCode ask override, keep Claude on `--permission-mode default`, leave coarse default-only runners unchanged, and warn for unverified RooCode safe-mode requests instead of implying broader parity
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`
- Notes: updated `docs/clis/README.md`, `docs/clis/opencode.md`, and `docs/clis/roocode.md`; removed the completed permission-mode backlog item from `TASKS.md`

## 2026-04-10

### Canonical `--print-config` added in Python and Rust
- Change: Python and Rust now support `ccc --print-config`, which prints a stable generated example `config.toml`; the canonical config schema is now `[defaults]`, `[abbreviations]`, and `[aliases.<name>]`, and the old legacy root-key fallbacks were removed from both implementations
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_parser_config.py`, `tests/test_runner.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/parser_tests.rs`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: updated `README.md`, `docs/llms.txt`, `docs/index.html`, `docs/clis/output-mode-porting.md`, `docs/clis/README.md`, the Python/Rust help text, and removed the backlog item from `TASKS.md`; the exact generated output is pinned by `tests/fixtures/config-example.toml`

## 2026-04-10

### Human-formatted output now honors FORCE_COLOR and NO_COLOR in Python and Rust
- Change: Python and Rust now resolve human-formatted TTY rendering with `FORCE_COLOR` / `NO_COLOR`, so emoji and ANSI prefixes can be forced on or suppressed independently of whether stdout is a TTY
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_json_output.py`, `tests/test_ccc_contract_impl.py`, `rust/tests/json_output_tests.rs`
- Notes: help text and the docs site now mention the environment override alongside the current TTY-based fallback

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

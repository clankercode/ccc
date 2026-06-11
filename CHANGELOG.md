# Changelog

## Unreleased
- No unreleased semantic changes.

## 0.3.4 - 2026-06-12
- Fixed opencode model format: now passes `provider/model` to opencode (e.g. `minimax/MiniMax-M3`) as required by its `--model` flag.

## 0.3.3 - 2026-06-12
- Fixed opencode `--model` flag: aliases with configured models (e.g. `@mm`, `@glm51`) now correctly pass `--model` to opencode instead of silently dropping it.

## 0.3.2 - 2026-06-12
- Added `--pure` flag when launching opencode to skip plugin auto-updates.

## 0.3.1 - 2026-05-05
- Added a `Configured aliases:` section to Python and Rust `ccc --help`, showing aliases visible from the current config chain before the runner checklist.
- Added short agent-facing help tips for checking `ccc config`, choosing `@alias` presets, and using `--` before literal prompt text that starts with control-like tokens.

## 0.3.0 - 2026-04-18
- Added `--timeout-secs <N>` in Python and Rust: `ccc` kills the wrapped runner after `N` seconds, prints `warning: timed out after N seconds; killed runner` to stderr, and exits with status `124`; invalid values (`0`, negatives, non-integers, missing value) are rejected at parse time.
- Exposed the watchdog through the library API: Rust `CommandSpec::with_timeout_secs`, `Run::timed_out()`, and Python `CommandSpec(timeout_secs=...)` / `CompletedRun.timed_out` let library callers opt into the same cancel semantics.

## 0.2.0 - 2026-04-17
- Added a typed Rust invocation API around `Client`, `Request`, `Plan`, `Run`, and typed transcript/output models, plus a compatibility sugar parser for `ccc`-style tokens.
- Changed the Rust CLI to plan and execute through the new library path instead of wiring directly through parser internals, while keeping top-level `help`, `version`, `config`, `config --edit`, and `add` flows CLI-owned.
- Improved the published Rust crate surface with stronger docs.rs metadata, crate-level API documentation, and clearer library examples for both typed requests and direct runner execution.

## 0.1.2 - 2026-04-17
- Fixed the Windows release build so `ccc` 0.1.2 could ship working Windows release artifacts.
- Adjusted Rust crate metadata and release packaging details needed for the Windows publish path.

## 0.1.1 - 2026-04-17
- Initial public release of `ccc` as a shared wrapper for coding-agent CLIs, with support for OpenCode, Claude Code, Codex, Kimi, Cursor Agent, Gemini CLI, RooCode, and Crush.
- Added the shared command surface: runner selectors, provider/model selection, thinking and visible-thinking controls, permission modes including `--yolo`, and output-mode sugar such as `.text`, `.json`, and `.fmt`.
- Added config-backed workflow support: `ccc config`, `ccc config --edit`, project-local `.ccc.toml` discovery and merge behavior, alias prompt fallbacks and `prompt_mode`, plus the interactive `ccc add` alias workflow.
- Added structured output handling across text, JSON, formatted, and streaming modes, including run artifact directories, parseable output-log footers, preserved unknown JSON, Codex JSONL support, and Gemini streaming JSON formatting.
- Added CLI polish and safety behavior including session-persistence warnings, top-level help and version handling, trusted-install version discovery, configurable OSC sanitization, and `FORCE_COLOR` / `NO_COLOR` support.
- Published the Rust crate alongside the CLI with the low-level `CommandSpec` and `Runner` API for direct subprocess execution.

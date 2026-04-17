# Changelog

## Unreleased
- Added a typed Rust invocation API around `Client`, `Request`, `Plan`, `Run`, and typed transcript/output models, plus a compatibility sugar parser for `ccc`-style tokens.
- Changed the Rust CLI to plan and execute through the new library path instead of wiring directly through parser internals, while keeping top-level `help`, `version`, `config`, `config --edit`, and `add` flows CLI-owned.
- Improved the Rust crate's docs.rs direction and implementation planning for the new library surface.

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

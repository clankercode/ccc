# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

Current implementation order:

- Python first: implemented
- Rust second: implemented
- then docs, C, TS, Elixir, and OCaml

Target CLIs include:

- OpenCode
- Claude / Claude Code
- Codex
- Kimi
- Gemini CLI
- Qwen Code
- similar terminal-first coding agents

Current scope:

- start a CLI process with a prompt or stdin payload
- capture stdout/stderr and exit status
- expose a small streaming interface
- keep the abstraction subprocess-oriented and easy to mock in tests

Cross-language CLI requirement:

- every language library should also bundle a CLI named `ccc`
- the `ccc` interface should have the same shape across languages
- the interface is not fully designed yet, but `ccc "<Prompt>"` must work
- library and CLI design should stay aligned so `precurl` can use the library layer while humans can use the same runner shape directly

First-pass `ccc` contract:

- `ccc "<Prompt>"`
- initial command shape maps to `opencode run "<Prompt>"`
- this is intentionally narrow and likely to grow later with explicit runner/model flags

Planned `ccc` syntax growth (design notes only, not implemented yet):

- the only implemented cross-language contract today is still `ccc "<Prompt>"`
- the next syntax shapes under consideration are:
  - `ccc @foo-bar "<Prompt>"` for a named alias or preset
  - `ccc +0 "<Prompt>"` through `ccc +4 "<Prompt>"` for thinking level selection
  - `ccc :provider:model "<Prompt>"` and `ccc :model "<Prompt>"` for explicit provider/model selection
  - runner selectors such as `c`, `cc`, `oc`, `k`, `rc`, `cr`, `codex`, `claude`, `opencode`, `kimi`, `roocode`, `crush`, and `pi`
- planned config support should eventually allow:
  - custom alias definitions and abbreviations
  - default provider selection
  - default model selection
  - bundled-runner defaults plus custom-name defaults
- combination rules, precedence, and final parsing order are intentionally still undecided
- until that design is locked, these forms are planned syntax only, not stable or implemented CLI behavior

Python package:

- import path: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`

Rust crate:

- crate name: `call-coding-clis`
- library name: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`

Planned roadmap:

- first-pass `ccc` CLI contract shared across implementations
- parser and config design for planned alias, thinking, runner, and provider/model selectors
- explicit design doc: `CCC_PARSER_CONFIG_DESIGN.md`
- docs for runner-specific patterns and prompt/output handling
- C bindings or C-facing interface notes
- TypeScript package
- Elixir package
- OCaml library

This repo is early-stage, but it now contains working Python code and tests instead of notes only.

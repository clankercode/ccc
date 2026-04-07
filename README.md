# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

Current implementation order:

- Python first: implemented
- Rust second: implemented
- TypeScript: implemented with runner and `ccc` coverage
- C: implemented with real subprocess execution in `ccc` plus reusable runner library
- next likely work: cross-language runner robustness and remaining design-first scaffolds

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
 - `precurl` uses the Rust library layer for delegated LLM analysis — see the [precurl SECURITY.md](../precurl/SECURITY.md) for threat model and prompt-injection mitigation details

First-pass `ccc` contract:

- `ccc "<Prompt>"`
- initial command shape maps to `opencode run "<Prompt>"`
- this is intentionally narrow and likely to grow later with explicit runner/model flags
- explicit shared behavior doc: `CCC_BEHAVIOR_CONTRACT.md`

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
- explicit contract doc for currently implemented behavior: `CCC_BEHAVIOR_CONTRACT.md`
- parser and config design for planned alias, thinking, runner, and provider/model selectors
- explicit design doc: `CCC_PARSER_CONFIG_DESIGN.md`
- remaining language scaffold doc: `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- cross-language startup-failure behavior normalization for implemented runners
- C `ccc` now executes commands through the runner library instead of printing them
- `CCC_REAL_OPENCODE` environment variable allows overriding the runner binary for testing
- Elixir design scaffold: `elixir/README.md`
- OCaml design scaffold: `ocaml/README.md`
- docs for runner-specific patterns and prompt/output handling
- C bindings or C-facing interface notes
- TypeScript package
- Elixir package
- OCaml library

Missing / possible future features:

- expanded `ccc` token parsing for `@alias`, `+0..+4`, `:provider:model`, `:model`, and runner selectors
- config-backed custom aliases, abbreviations, and default provider/model resolution
- cross-language normalization of streaming event shapes and exit-code behavior
- broader cross-language normalization of process-start failure handling beyond the current Python, Rust, C, and TypeScript coverage
- startup-failure coverage now exists across Python, Rust, TypeScript, and C, but deeper event-shape parity is still open
- richer stdin/cwd/env coverage and docs for every implementation
- C `ccc` now executes commands through the runner library, closing the last major scaffold gap
- Elixir and OCaml implementations once local toolchains are available or design-first scaffolds are written
- v2 idea: parse structured JSON output from supported runners and render it consistently
- v2 idea: templated or user-customizable rendering for structured output so humans can choose how `ccc` presents results

This repo is early-stage, but it now contains working Python code and tests instead of notes only.

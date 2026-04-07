# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

Current implementation order:

- Python first
- Rust second
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

Python package:

- import path: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`

Planned roadmap:

- Rust crate matching the first-pass runner abstraction
- first-pass `ccc` CLI contract shared across implementations
- docs for runner-specific patterns and prompt/output handling
- C bindings or C-facing interface notes
- TypeScript package
- Elixir package
- OCaml library

This repo is early-stage, but it now contains working Python code and tests instead of notes only.

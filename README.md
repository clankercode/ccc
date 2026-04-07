# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

## Implementation Status

### Implemented (full runner + ccc CLI)

- **Python**: implemented — `call_coding_clis` package with `CommandSpec`, `Runner`, `ccc` CLI
- **Rust**: implemented — `call-coding-clis` crate with `CommandSpec`, `Runner`, `ccc` binary
- **TypeScript**: implemented — runner + `ccc` CLI with streaming support
- **C**: implemented — reusable runner library (`runner.c`/`runner.h`) plus `ccc` binary

### Planned — Full Implementation

- **C++**: modern C++ (C++17+), leveraging RAII, `std::process` or POSIX APIs, smart pointers, templates
- **PureScript**: runs on Node.js backend, `purs` compile target, subprocess via Node `child_process`
- **Zig**: native cross-compilation story, `std.process` for subprocess, comptime for build-time config
- **D**: system-level access with GC-optional, `std.process` for subprocess execution
- **F#**: .NET ecosystem, `System.Diagnostics.Process` for subprocess, functional API design
- **Haskell**: strong type system, `process` package for subprocess, monadic runner abstraction
- **Nim**: Python-like syntax compiled to C, `osproc` module for subprocess execution
- **Go**: popular for CLI tools, `os/exec` package, goroutine-based streaming
- **Crystal**: Ruby-like syntax compiled to native, `Process` stdlib module
- **Ruby**: `IO.popen` / `Open3` for subprocess, gem packaging
- **Perl**: `system`, `open3`, or `IPC::Run` for subprocess, CPAN distribution
- **PHP**: `proc_open` / `symfony/process` for subprocess, Composer package
- **VBScript**: WScript.Shell `Exec`/`Run` for subprocess, Windows-native
- **x86-64 ASM**: raw Linux syscalls (`execve`, `write`, `exit`), minimal ELF binary `ccc`
- **OCaml**: `Unix` module for subprocess, dune build — **goal: prove as much about the system as possible** using OCaml's type system and optionally formal verification tools (Why3/Alt-Ergo)

### Planned — Full Implementation (continued)

- **Elixir**: `System.cmd` or ports-based wrapper, bundled `ccc` escript or Mix task; Erlang fallback if Elixir toolchain issues arise

## Target CLIs

- OpenCode
- Claude / Claude Code
- Codex
- Kimi
- Gemini CLI
- Qwen Code
- similar terminal-first coding agents

## Current Scope

- start a CLI process with a prompt or stdin payload
- capture stdout/stderr and exit status
- expose a small streaming interface
- keep the abstraction subprocess-oriented and easy to mock in tests

## Cross-Language CLI Requirement

- every language library should also bundle a CLI named `ccc`
- the `ccc` interface should have the same shape across languages
- the interface is not fully designed yet, but `ccc "<Prompt>"` must work
- library and CLI design should stay aligned so `precurl` can use the library layer while humans can use the same runner shape directly
- `precurl` uses the Rust library layer for delegated LLM analysis — see the [precurl SECURITY.md](../precurl/SECURITY.md) for threat model and prompt-injection mitigation details

## First-Pass `ccc` Contract

- `ccc "<Prompt>"`
- initial command shape maps to `opencode run "<Prompt>"`
- this is intentionally narrow and likely to grow later with explicit runner/model flags
- explicit shared behavior doc: `CCC_BEHAVIOR_CONTRACT.md`

## Planned `ccc` Syntax Growth (design notes only, not implemented yet)

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

## Python Package

- import path: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`

## Rust Crate

- crate name: `call-coding-clis`
- library name: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`

## Planned Roadmap

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

## Missing / Possible Future Features

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

## Licensing

Unlicense — see `UNLICENSE`.

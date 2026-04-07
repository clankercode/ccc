# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

## Running All Tests

```bash
./run_all_tests.sh
```

This runs all 10 test suites (8 language-specific + 2 cross-language) and prints a color-coded checklist:

```
  PASS  python: runner + prompt_spec
  PASS  rust: cargo test
  PASS  typescript: node --test
  PASS  c: make test
  PASS  go: go test
  PASS  ruby: test suite
  PASS  perl: prove
  PASS  cpp: cmake build + gtest
  PASS  contract: ccc CLI behavior (8 languages)
  PASS  harness: mock binary behavior (8 langs × 9 cases)

  Total: 10  Passed: 10  Failed: 0  Skipped: 0
```

### Individual Test Commands

| Language | Command |
|----------|---------|
| Python | `PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_ccc_contract` |
| Rust | `cd rust && cargo test` |
| TypeScript | `node --test typescript/tests/runner.test.mjs` |
| C | `cd c && make test` |
| Go | `cd go && go test ./...` |
| Ruby | `cd ruby && ruby -Ilib -Itest test/test_*.rb` |
| Perl | `cd perl && prove -v t/` |
| C++ | `cmake -B cpp/build -S cpp && cmake --build cpp/build --target ccc_tests && ./cpp/build/tests/ccc_tests` |
| Cross-language | `PYTHONPATH=python python3 -m unittest tests.test_ccc_contract tests.test_harness` |

## Implementation Status

### Implemented (full runner + ccc CLI + cross-language tests)

- **Python** — `call_coding_clis` package, `CCC_REAL_OPENCODE` support
- **Rust** — `call-coding-clis` crate, concurrent streaming, `CCC_REAL_OPENCODE` support
- **TypeScript** — runner + `ccc` CLI with streaming, `CCC_REAL_OPENCODE` support
- **C** — reusable runner library (`runner.c`/`runner.h`) plus `ccc` binary
- **Go** — `go/ccc.go` library with goroutine-based streaming, `ccc` CLI
- **Ruby** — `CallCodingClis` module with runner/stream, `ccc` CLI
- **Perl** — `Call::Coding::Clis` with runner, `ccc` CLI
- **C++** — C++17 with GoogleTest, cmake build, `ccc` CLI

### Planned (PLAN.md exists in each directory)

PureScript, Zig, D, F#, Haskell, Nim, Crystal, PHP, VBScript, x86-64 ASM, Elixir, OCaml (with formal verification)

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

- implement remaining 12 languages (see `PLAN.md` in each directory)
- parser and config design for planned alias, thinking, runner, and provider/model selectors: `CCC_PARSER_CONFIG_DESIGN.md`
- language scaffold doc: `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- cross-language test harness design: `TEST_HARNESS_PLAN.md`
- expanded `ccc` token parsing for `@alias`, `+0..+4`, `:provider:model`, `:model`, and runner selectors

## Missing / Possible Future Features

- expanded `ccc` token parsing for `@alias`, `+0..+4`, `:provider:model`, `:model`, and runner selectors
- config-backed custom aliases, abbreviations, and default provider/model resolution
- richer stdin/cwd/env coverage and docs for every implementation
- v2: parse structured JSON output from supported runners and render it consistently
- v2: templated or user-customizable rendering for structured output

## Licensing

Unlicense — see `UNLICENSE`.

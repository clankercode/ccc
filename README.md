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

## Running One Implementation

When working on a single language, use the targeted wrapper instead of the full repo sweep:

```bash
./test_impl.sh <language>
```

Examples:

```bash
./test_impl.sh c
./test_impl.sh rust
./test_impl.sh typescript
```

This runs that implementation's unit tests plus the targeted cross-language contract and mock harness checks for the same language only. Use `./run_all_tests.sh` only when you intentionally want the whole repository run.

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
| Cross-language | `PYTHONPATH=python python3 -m unittest tests.test_ccc_contract && PYTHONPATH=python python3 tests/test_harness.py all -v` |

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
- Python and Rust also support free-order control tokens before the prompt, `--` to force literal prompt text, `--show-thinking` / `--no-show-thinking`, and `--yolo` / `-y`

## First-Pass `ccc` Contract

- `ccc "<Prompt>"`
- initial command shape maps to `opencode run "<Prompt>"`
- this is intentionally narrow and likely to grow later with explicit runner/model flags
- explicit shared behavior doc: `CCC_BEHAVIOR_CONTRACT.md`

## Current Python/Rust Extended `ccc` Syntax

- Python and Rust currently accept control tokens in any order before the prompt:
  - runner selectors such as `c`, `cx`, `cc`, `oc`, `k`, `rc`, `cr`, `codex`, `claude`, `opencode`, `kimi`, `roocode`, `crush`, and `pi`
  - `+0..+4` thinking levels
  - `:provider:model` and `:model`
  - `@name` for preset lookup with agent fallback; presets can also define a default prompt, and alias `prompt_mode = "prepend"|"append"` can compose alias prompt text around an explicitly supplied prompt
  - `-h` / `--help` wins anywhere in argv and prints help immediately
  - Python and Rust search project-local `.ccc.toml` files upward from the current directory and override the global config chain
  - `ccc config` prints the resolved config file path and raw contents, preferring `CCC_CONFIG`, then project-local `.ccc.toml`, then `XDG_CONFIG_HOME/ccc/config.toml`, then `~/.config/ccc/config.toml`
  - `ccc add [-g] <alias>` starts a line-prompt wizard for writing `[aliases.<name>]` config; flags such as `--runner`, `--model`, `--prompt`, and `--prompt-mode` can prefill values, and `--yes` writes non-interactively
  - `formatted`, `stream-formatted`, and `ccc add` menu prompts honor `FORCE_COLOR` / `NO_COLOR` before falling back to TTY detection
  - `--print-config` to print the canonical example `config.toml`
  - `--permission-mode safe|auto|yolo|plan`
  - `--save-session` to explicitly allow normal runner session persistence
  - `--cleanup-session` to try post-run cleanup when a runner lacks a no-persist flag
  - `--show-thinking` / `--no-show-thinking`
  - `--yolo` / `-y`
- `--` forces the rest of argv to be treated as prompt text, even if it starts with control-like tokens
- Python and Rust currently use `claude -p --no-session-persistence`, `codex exec --ephemeral`, and `crush run` for non-interactive invocation
- By default Python and Rust avoid saved sessions where the selected CLI supports it; OpenCode, Kimi, Crush, and RooCode warn that the runner may save a session unless `--save-session` or `--cleanup-session` is used
- `ccc --print-config` is the source of truth for the current canonical config schema: `[defaults]`, `[abbreviations]`, and `[aliases.<name>]`
- `ccc config` is the source of truth for which config file currently resolves in the active shell
- `ccc add <alias>` writes the resolved config file shown by `ccc config`; when no config exists it creates a new global config under `XDG_CONFIG_HOME/ccc/config.toml` or `~/.config/ccc/config.toml`, and `-g` forces the effective global config instead of a project-local file

## Planned `ccc` Syntax Growth (design notes only, not fully rolled out yet)

- planned config support should eventually allow:
  - custom alias definitions and abbreviations
  - default provider selection
  - default model selection
  - bundled-runner defaults plus custom-name defaults
- broader multi-language rollout is still pending for the extended control-token surface

## Python Package

- import path: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`, `render_example_config`

## Rust Crate

- crate name: `call-coding-clis`
- library name: `call_coding_clis`
- current API: `CommandSpec`, `CompletedRun`, `Runner`, `render_example_config`

## Planned Roadmap

- living backlog of unfinished work: [TASKS.md](TASKS.md)
- implement remaining 12 languages (see `PLAN.md` in each directory)
- parser and config design for planned alias, thinking, runner, and provider/model selectors: `CCC_PARSER_CONFIG_DESIGN.md`
- language scaffold doc: `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- cross-language test harness design: `TEST_HARNESS_PLAN.md`
- expanded `ccc` token parsing for `@name`, `+0..+4`, `:provider:model`, `:model`, and runner selectors
- future advanced tool allow/deny design note: [docs/clis/allow-deny-tool-plan.md](docs/clis/allow-deny-tool-plan.md)
- shared model-thinking capability source of truth and refresh instructions: [docs/clis/model-capabilities.json](docs/clis/model-capabilities.json) and [docs/clis/updating-model-capabilities.md](docs/clis/updating-model-capabilities.md)

## Missing / Possible Future Features

- expanded `ccc` token parsing for `@name`, `+0..+4`, `:provider:model`, `:model`, and runner selectors
- config-backed presets, runner abbreviations, agent defaults, and provider/model resolution
- richer stdin/cwd/env coverage and docs for every implementation
- v2: parse structured JSON output from supported runners and render it consistently
- v2: templated or user-customizable rendering for structured output

## Licensing

Unlicense — see `UNLICENSE`.

# call-coding-clis

Small libraries for calling coding CLIs from normal programs.

## Running All Tests

```bash
./run_all_tests.sh
```

This runs every implementation's unit/build checks plus the cross-language contract and mock-harness checks, then prints a color-coded checklist:

```
  PASS  python: runner + prompt_spec
  PASS  rust: cargo test
  PASS  typescript: node --test
  PASS  c: make test
  PASS  go: go test
  PASS  ruby: test suite
  PASS  perl: prove
  PASS  cpp: cmake build + gtest
  ...
  SKIP  vbscript: test suite (Windows only)
  PASS  contract: ccc CLI behavior (legacy + @name matrix)
  PASS  harness: mock binary behavior (16 langs × 9 cases)

  Total: 22  Passed: 21  Failed: 0  Skipped: 1
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

## Build

```bash
just build
```

This builds the Rust binary and runs a Python compile check. Both Python and Rust read the repo-root `VERSION` file for `ccc --version`, so update that file when you want to bump the reported build version.

### Individual Test Commands

| Language | Command |
|----------|---------|
| Python | `PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_parser_config tests.test_json_output tests.test_run_artifacts` |
| Rust | `cd rust && cargo test` |
| TypeScript | `node --test typescript/tests/runner.test.mjs` |
| C | `cd c && make test` |
| Go | `cd go && go test ./...` |
| Ruby | `cd ruby && ruby -Ilib -Itest test/test_*.rb` |
| Perl | `cd perl && prove -v t/` |
| C++ | `cmake -B cpp/build -S cpp && cmake --build cpp/build --target ccc_tests && ./cpp/build/tests/ccc_tests` |
| Cross-language | `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py <language> -v && PYTHONPATH=. python3 tests/test_harness.py <language> -v` |

## Implementation Status

### Implemented (runner + `ccc` CLI + cross-language tests)

- **Python** — `call_coding_clis` package, real-runner override env support
- **Rust** — `call-coding-clis` crate, concurrent streaming, real-runner override env support
- **TypeScript** — runner + `ccc` CLI with streaming, `CCC_REAL_OPENCODE` support
- **C** — reusable runner library (`runner.c`/`runner.h`) plus `ccc` binary
- **Go** — `go/ccc.go` library with goroutine-based streaming, `ccc` CLI
- **Ruby** — `CallCodingClis` module with runner/stream, `ccc` CLI
- **Perl** — `Call::Coding::Clis` with runner, `ccc` CLI
- **C++** — C++17 with GoogleTest, cmake build, `ccc` CLI
- **Zig, D, F#, PHP, PureScript, x86-64 ASM, OCaml, Crystal, Haskell, Elixir, Nim** — `ccc` implementations covered by targeted contract/harness checks

### Planned / Follow-Up Tracked In `PLAN.md`

Implementation-specific follow-up work is tracked in each language's `PLAN.md`. VBScript remains planned.

## Target CLIs

- OpenCode
- Claude / Claude Code
- Codex
- Kimi
- Gemini CLI
- Cursor Agent
- RooCode
- Crush
- Qwen Code
- similar terminal-first coding agents

## Current Scope

- start a CLI process with a prompt or stdin payload
- capture stdout/stderr and exit status
- expose a small streaming interface
- keep the abstraction subprocess-oriented and easy to mock in tests
- write a stable per-run artifact directory under the platform state root, with a client-prefixed run folder such as `opencode-<run-id>` and a parseable stderr footer for scripts

## Cross-Language CLI Requirement

- every language library should also bundle a CLI named `ccc`
- the `ccc` interface should have the same shape across languages
- `ccc "<Prompt>"` must work everywhere; Python and Rust carry the reference extended CLI surface
- library and CLI design should stay aligned so `precurl` can use the library layer while humans can use the same runner shape directly
- `precurl` uses the Rust library layer for delegated LLM analysis — see the [precurl SECURITY.md](../precurl/SECURITY.md) for threat model and prompt-injection mitigation details
- Python and Rust also support free-order control tokens before the prompt, `--` to force literal prompt text, `--show-thinking` / `--no-show-thinking`, and `--yolo` / `-y`
- `-v` / `--version` prints the shared build version plus resolved client versions

## First-Pass `ccc` Contract

- `ccc "<Prompt>"`
- initial command shape maps to `opencode run "<Prompt>"`
- this is intentionally narrow and likely to grow later with explicit runner/model flags
- explicit shared behavior doc: `CCC_BEHAVIOR_CONTRACT.md`

## Current Python/Rust Extended `ccc` Syntax

- Python and Rust currently accept control tokens in any order before the prompt:
  - runner selectors such as `c`, `cx`, `cc`, `oc`, `k`, `cu`, `g`, `rc`, `cr`, `codex`, `claude`, `opencode`, `kimi`, `cursor`, `gemini`, `roocode`, and `crush`
  - `+0..+4` thinking levels
  - `:provider:model` and `:model`
  - `@name` for preset lookup; if no preset exists, runner names such as `@k` select that runner before ordinary agent fallback; presets can also define a default prompt, and alias `prompt_mode = "prepend"|"append"` can compose alias prompt text around an explicitly supplied prompt
  - `help`, `-h`, and `--help` win anywhere in argv and print help immediately
  - `ccc --help` lists configured aliases visible from the current directory and includes short agent tips for checking config, choosing aliases, and using `--` for literal prompt text
  - Python and Rust search project-local `.ccc.toml` files upward from the current directory and override the global config chain
  - `ccc config` prints every existing config file path and raw contents in merge order: `~/.config/ccc/config.toml`, `XDG_CONFIG_HOME/ccc/config.toml`, then the nearest project-local `.ccc.toml`; `CCC_CONFIG` still wins alone when it points at an existing file
  - `ccc config --edit` opens the selected config in `$EDITOR`; add `--user` to edit the XDG/home user config or `--local` to edit the nearest `.ccc.toml` (creating one in the current directory if none exists)
  - `ccc add [-g] <alias>` starts a line-prompt wizard for writing `[aliases.<name>]` config; flags such as `--runner`, `--model`, `--prompt`, and `--prompt-mode` can prefill values, and `--yes` writes non-interactively
  - `formatted`, `stream-formatted`, and `ccc add` menu prompts honor `FORCE_COLOR` / `NO_COLOR` before falling back to TTY detection
  - formatted modes always keep unhandled structured JSON lines in the run transcript; `CCC_FWD_UNKNOWN_JSON` controls whether they are also forwarded to stderr and currently defaults on
  - `--print-config` to print the canonical example `config.toml`
  - `--permission-mode safe|auto|yolo|plan`
  - `--save-session` to explicitly allow normal runner session persistence
  - `--cleanup-session` to try post-run cleanup when a runner lacks a no-persist flag
  - `--output-log-path` / `--no-output-log-path` to enable or suppress the final stderr footer that points at the run artifact directory
  - `--show-thinking` / `--no-show-thinking`
  - `--timeout-secs <N>` kills the wrapped runner after `N` seconds, prints `warning: timed out after N seconds; killed runner` to stderr, and exits with status `124`
  - `--yolo` / `-y`
- `--` forces the rest of argv to be treated as prompt text, even if it starts with control-like tokens
- Python and Rust currently use `claude -p --no-session-persistence`, `codex exec --ephemeral`, `cursor-agent --print --trust`, `gemini --prompt`, and `crush run` for non-interactive invocation
- By default Python and Rust avoid saved sessions where the selected CLI supports it; OpenCode, Kimi, Cursor, Gemini, Crush, and RooCode warn that the runner may save a session unless `--save-session` or `--cleanup-session` is used
- `ccc --print-config` is the source of truth for the current canonical config schema: `[defaults]`, `[abbreviations]`, and `[aliases.<name>]`
- `ccc config` is the source of truth for which config files currently resolve in the active shell
- `ccc config --edit [--user|--local]` opens the selected config in `$EDITOR`; user config means `XDG_CONFIG_HOME/ccc/config.toml` when XDG is set, otherwise `~/.config/ccc/config.toml`, and local config means the nearest existing `.ccc.toml` or a new `.ccc.toml` in the current directory
- `ccc add <alias>` writes the active write target: project-local config when present, otherwise the effective global config; when no config exists it creates a new global config under `XDG_CONFIG_HOME/ccc/config.toml` or `~/.config/ccc/config.toml`, and `-g` forces the effective global config instead of a project-local file
- `ccc` writes `output.txt` plus exactly one transcript file in each run directory: `transcript.txt` for text and human transcript paths, `transcript.jsonl` for JSON-oriented paths; `text` requests that are upgraded into structured streaming still use `transcript.txt`
- each run directory is client-prefixed, for example `opencode-<run-id>`
- `ccc` prints a stable stderr footer in the form `>> ccc:output-log >> /abs/path/to/run-dir` unless `--no-output-log-path` is set

## Planned `ccc` Syntax Growth (design notes only, not fully rolled out yet)

- planned config support should eventually allow:
  - broader multi-language rollout for the Python/Rust config surface
  - multi-provider, multi-preset, and multi-alias routing policies
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
- broader rollout of expanded `ccc` token parsing for `@name`, `+0..+4`, `:provider:model`, `:model`, and runner selectors beyond Python/Rust
- future advanced tool allow/deny design note: [docs/clis/allow-deny-tool-plan.md](docs/clis/allow-deny-tool-plan.md)
- shared model-thinking capability source of truth and refresh instructions: [docs/clis/model-capabilities.json](docs/clis/model-capabilities.json) and [docs/clis/updating-model-capabilities.md](docs/clis/updating-model-capabilities.md)

## Missing / Possible Future Features

- broader rollout of Python/Rust config-backed presets, runner abbreviations, agent defaults, and provider/model resolution
- richer stdin/cwd/env coverage and docs for every implementation
- v2: templated or user-customizable rendering for structured output
- v2: HTTP/HTTPS delivery of run artifacts and final output logs, tracked in [TASKS.md](TASKS.md)

## Licensing

Unlicense — see `UNLICENSE`.

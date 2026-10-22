# CCC Behavior Contract

## Purpose

Capture the current shared `ccc` behavior across implemented languages so the library and CLI surfaces do not drift while the broader parser/config design is still evolving.

## Current Implemented Contract

The only stable user-facing contract today is:

```text
ccc "<Prompt>"
```

That contract currently means:

- exactly one positional prompt argument
- prompts are trimmed of leading/trailing whitespace before use
- empty or whitespace-only prompts are rejected
- the first-pass command shape resolves to `opencode run "<trimmed-Prompt>"`

## Cross-Language Expectations

For every implementation that claims `ccc` support:

- `ccc "<Prompt>"` must be accepted
- missing or invalid prompt input must fail with a non-zero exit code
- the first-pass prompt-to-command-spec mapping must be consistent
- library and CLI layers should expose the same underlying command-shape behavior

## Implemented Languages

Python and Rust runner checklists display `[+]` or `[-]`, the executable name, version/status, and version-lookup duration in aligned columns. `cursor-agent` appears directly, without a duplicate runner name. The monotonic timer covers metadata discovery and any fallback version command, excluding executable resolution and rendering. Installed runners show elapsed milliseconds to one decimal place even if no version is returned (`found`); missing executables show `not found` and `-` for timing. Durations strictly greater than 50 ms are red when color is enabled. Nonempty `FORCE_COLOR` takes precedence over nonempty `NO_COLOR`; otherwise color follows the destination stream's TTY status. Help and version output use stdout; usage errors use stderr. `--version` / `-v` apply the same columns to resolved clients and retain the unresolved count.

Python and Rust support standalone controls: CLI `--standalone` / `--no-daemon` select true, `--no-standalone` selects false, and defaults/aliases can set `standalone`. CLI overrides aliases, then defaults. True emits `codex --no-daemon exec` or `opencode run --standalone`; false omits the override and permits upstream defaults. Other runners warn when true is requested. Codex internal in-process app-server operation remains available.

Python and Rust map `+ultra` / `+6` and alias `thinking = 6` to Codex `-c model_reasoning_effort=ultra`; other runners clamp to their supported maximum. Effort and service tier are independent. OpenCode uses `opencode run` without the unsupported `--pure` flag.

Python and Rust support Codex service tiers through `--service-tier default|fast|priority|ultrafast`, `[defaults].service_tier`, and `[aliases.<name>].service_tier`. Explicit CLI controls take precedence over aliases, then defaults. The last CLI tier control wins; `--fast` selects fast and `--no-fast` selects default. Omitted fields inherit upstream configuration; explicit default overrides an upstream faster tier. Other runners warn and ignore tier selection. Invalid tiers fail. Alias creation/editing, generated config, help summaries, and the wizard preserve this distinction. Codex auto permissions use `-c 'approval_policy="on-request"' --sandbox workspace-write` instead of the removed `--full-auto` flag.

### Python

- supports first-pass `ccc "<Prompt>"`
- supports `--show-thinking` / `--no-show-thinking` with config-backed `show_thinking` (default off)
- exposes `build_prompt_spec`
- runner supports `run` and `stream`
- `CCC_REAL_OPENCODE` env var support
- alias `fallback_models` retries after a capacity or overload error that happens before assistant output; `glm-5.3`, `llmp-glm-5-3`, and `glm-5.3-flash` switch to the grok runner; JSON and formatted output from that retry is parsed with the fallback runner's schema; MiniMax, Claude, and Astra model ids are not fallback targets

### Rust

- supports first-pass `ccc "<Prompt>"`
- supports `--show-thinking` / `--no-show-thinking` with config-backed `show_thinking` (default off)
- exposes `build_prompt_spec`
- runner supports `run` and `stream` (real concurrent streaming via threads)
- `CCC_REAL_OPENCODE` env var support
- alias `fallback_models` retries after a capacity or overload error that happens before assistant output; `glm-5.3`, `llmp-glm-5-3`, and `glm-5.3-flash` switch to the grok runner; JSON and formatted output from that retry is parsed with the fallback runner's schema; MiniMax, Claude, and Astra model ids are not fallback targets

### TypeScript

- supports first-pass `ccc "<Prompt>"`
- exposes `buildPromptSpec`
- runner supports `run` and `stream`
- CLI now forwards streamed output from the runner path

### C

- supports first-pass `ccc "<Prompt>"`
- runner library (`runner.c`/`runner.h`) provides subprocess execution with stdout/stderr capture, stdin/cwd/env support, and startup-failure reporting
- `ccc` CLI executes commands through the runner library and forwards stdout/stderr and exit codes
- `CCC_REAL_OPENCODE` environment variable allows overriding the runner binary for testing
- passes all four cross-language contract tests (happy path, empty prompt, missing prompt, whitespace prompt)

### Go

- supports first-pass `ccc "<Prompt>"`
- exposes `BuildPromptSpec`
- runner supports `Run` and `Stream` (real goroutine-based streaming)
- `CCC_REAL_OPENCODE` env var support

### Ruby

- supports first-pass `ccc "<Prompt>"`
- exposes `build_prompt_spec` via `CallCodingClis` module
- runner supports `run` and `stream`
- `CCC_REAL_OPENCODE` env var support

### Perl

- supports first-pass `ccc "<Prompt>"`
- exposes `build_prompt_spec` via `Call::Coding::Clis`
- runner supports `run`
- `CCC_REAL_OPENCODE` env var support

### C++

- supports first-pass `ccc "<Prompt>"`
- exposes `build_prompt_spec`
- runner supports `run` and `stream`
- `CCC_REAL_OPENCODE` env var support
- CMake build with GoogleTest

## Non-Contract Behavior

The following are planned but not yet stable contract:

- `@alias`
- `+0..+5`
- `:provider:model`
- `:model`
- runner selector shortcuts
- config-backed alias/default resolution

Those remain design-stage behavior only until the parser/config design is finalized and multiple implementations land it consistently.

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

### Python

- supports first-pass `ccc "<Prompt>"`
- supports `--show-thinking` / `--no-show-thinking` with config-backed `show_thinking` (default off)
- exposes `build_prompt_spec`
- runner supports `run` and `stream`
- `CCC_REAL_OPENCODE` env var support

### Rust

- supports first-pass `ccc "<Prompt>"`
- supports `--show-thinking` / `--no-show-thinking` with config-backed `show_thinking` (default off)
- exposes `build_prompt_spec`
- runner supports `run` and `stream` (real concurrent streaming via threads)
- `CCC_REAL_OPENCODE` env var support

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
- `+0..+4`
- `:provider:model`
- `:model`
- runner selector shortcuts
- config-backed alias/default resolution

Those remain design-stage behavior only until the parser/config design is finalized and multiple implementations land it consistently.

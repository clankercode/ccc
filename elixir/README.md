# Elixir Scaffold

## Purpose

Design-first scaffold for a future Elixir implementation of `call-coding-clis`.

## Current Status

- design-only scaffold
- no implementation or local toolchain assumptions yet

## Intended Package Shape

- library wrapper for subprocess invocation
- bundled `ccc` entrypoint later

## Minimal First-Pass Contract

- `ccc "<Prompt>"`
- maps to the shared prompt-spec behavior only

See also:

- `CCC_BEHAVIOR_CONTRACT.md`
- `CCC_PARSER_CONFIG_DESIGN.md`

## Candidate Implementation Directions

- `System.cmd` path for simple run behavior
- ports-based path for streaming behavior
- final choice deferred until implementation

## Proposed Public Surface

- invocation-spec builder
- completed-run result
- runner abstraction with `run`/`stream` intent

## Open Questions

- Mix task vs escript for `ccc`
- streaming API shape
- test harness strategy

## Non-Goals For This Scaffold

- expanded parser behavior
- config schema
- parity claims beyond the current `ccc "<Prompt>"` contract

# Roadmap Language Scaffolds

## Purpose

Make the remaining `call-coding-clis` language roadmap concrete enough that later implementation work has a clear starting point.

## Shared Expectations

Each language target should eventually provide:

- a library for invoking coding CLIs as subprocesses
- a bundled `ccc` CLI with the same interface shape
- runner selection support consistent with the shared parser/config design
- a testable execution abstraction

## C

- likely shape: small C library wrapping process spawning plus a thin `ccc` binary
- current state: reusable runner library plus smoke-level `ccc` coverage are implemented
- likely next step: decide whether to wire `ccc` through the runner library without destabilizing the shared contract

## TypeScript

- likely shape: package wrapping `child_process.spawn`
- current state: `CommandSpec`/`Runner`/`ccc` implementation exists with subprocess and stream coverage
- likely next step: continue tightening cross-language error and event-shape parity

## Elixir

- likely shape: wrapper around `System.cmd` or ports, with a small `ccc` Mix task or escript
- initial deliverable: process abstraction notes and `ccc` command contract mapping
- current scaffold doc: `elixir/README.md`

## OCaml

- likely shape: library over `Unix` process APIs plus a small `ccc` executable
- initial deliverable: module-level API sketch and subprocess/streaming notes
- current scaffold doc: `ocaml/README.md`

## Ordering Notes

- Python and Rust are implemented first
- parser/config design should stabilize before the remaining `ccc` ports claim compatibility
- TypeScript and C are now implemented at different maturity levels
- Elixir and OCaml remain design-first scaffolds

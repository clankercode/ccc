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
- initial deliverable: design-first notes around process APIs, streaming, and memory ownership

## TypeScript

- likely shape: package wrapping `child_process.spawn`
- initial deliverable: mirror `CommandSpec`, `CompletedRun`, `Runner`, then add `ccc`

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
- TypeScript is probably the next highest-leverage implementation after `precurl` stabilizes
- C, Elixir, and OCaml can start as design-oriented scaffold docs before code

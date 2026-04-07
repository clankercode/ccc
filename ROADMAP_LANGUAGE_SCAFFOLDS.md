# Roadmap Language Scaffolds

## Purpose

Make the remaining `call-coding-clis` language roadmap concrete enough that later implementation work has a clear starting point.

## Shared Expectations

Each language target should eventually provide:

- a library for invoking coding CLIs as subprocesses
- a bundled `ccc` CLI with the same interface shape
- runner selection support consistent with the shared parser/config design
- a testable execution abstraction

## Current Feature Parity Matrix

| Feature | Python | Rust | TypeScript | C |
|---------|--------|------|------------|---|
| `build_prompt_spec` | yes | yes | yes (`buildPromptSpec`) | yes (`ccc_build_prompt_command`) |
| `CommandSpec` | yes | yes | yes | yes (`CodingCliCommandSpec`) |
| `Runner.run` | yes | yes | yes | yes (`run_command`) |
| `Runner.stream` | yes | yes (non-streaming impl) | yes | no |
| `ccc` CLI binary | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes (via `trim_in_place` + `ccc_build_prompt_command`) |
| Empty prompt rejection | yes | yes | yes | yes |
| Whitespace-only rejection | yes | yes | yes | yes |
| Stdin text support | yes | yes | yes | yes |
| CWD support | yes | yes | yes | yes |
| Env override support | yes | yes | yes | yes |
| Startup failure reporting | yes | yes | yes | yes |
| Exit code forwarding | yes | yes (via `std::process::exit`) | yes | yes |
| Stderr forwarding | yes | yes | yes | yes |
| Runner prefix override env | no | no | yes (`CCC_RUNNER_PREFIX_JSON`) | yes (`CCC_REAL_OPENCODE`) |
| Streaming CLI output | no (uses `.run()`) | no (uses `.run()`) | yes (uses `.stream()`) | no |
| Cross-language contract tests | yes | yes | yes | yes |

## C

- likely shape: small C library wrapping process spawning plus a thin `ccc` binary
- current state: reusable runner library plus smoke-level `ccc` coverage are implemented
- known issues: `ccc_build_prompt_command` computes trimmed index but now uses it (fixed); runner prefix env is `CCC_REAL_OPENCODE` only

## TypeScript

- likely shape: package wrapping `child_process.spawn`
- current state: `CommandSpec`/`Runner`/`ccc` implementation exists with subprocess and stream coverage
- known issues: only language with `runnerPrefix` env var support and streaming CLI output

## Elixir

- likely shape: wrapper around `System.cmd` or ports, with a small `ccc` Mix task or escript
- initial deliverable: process abstraction notes and `ccc` command contract mapping
- current scaffold doc: `elixir/README.md`
- status: planned full implementation (Erlang fallback if Elixir toolchain issues arise)
- subprocess: `System.cmd/3` for run, `Port` for streaming

## OCaml

- likely shape: library over `Unix` process APIs plus a small `ccc` executable
- initial deliverable: module-level API sketch and subprocess/streaming notes
- current scaffold doc: `ocaml/README.md`
- status: design-only
- **special goal**: prove as much about the system as possible using OCaml's type system and optionally formal verification tools (Why3/Alt-Ergo)

## C++

- likely shape: modern C++17+ library with RAII subprocess management, `ccc` binary
- key features to leverage: smart pointers, templates, `std::filesystem`, `std::optional`, move semantics
- subprocess: POSIX `fork`/`exec` or `std::process` (if available) with pipe management
- packaging: CMake or Meson build, header-only or static library option

## PureScript

- likely shape: library targeting Node.js backend via `purs`, `ccc` CLI as Node script
- subprocess: Node `child_process` bindings through FFI
- packaging: Spago package, `ccc` as a PureScript-compiled Node entrypoint

## Zig

- likely shape: single-file library + `ccc` binary using `std.process`
- key features: comptime for build-time config, cross-compilation, no hidden control flow
- subprocess: `std.process.Child` API
- packaging: `build.zig` with library + binary targets

## D

- likely shape: library using `std.process` for subprocess, `ccc` binary
- key features: GC-optional, templates, ranges, `scope` for RAII-like resource management
- packaging: Dub package

## F#

- likely shape: library using `System.Diagnostics.Process`, `ccc` console app
- key features: functional API design, discriminated unions for results, async workflows
- packaging: NuGet package, dotnet CLI tool

## Haskell

- likely shape: library using the `process` package, `ccc` executable
- key features: strong type system, monadic runner abstraction, lazy I/O caution
- packaging: Cabal or Stack package

## Nim

- likely shape: library using `osproc` module, `ccc` binary
- key features: Python-like syntax, compiles to C, macros for DSL building
- packaging: Nimble package

## Go

- likely shape: library using `os/exec`, `ccc` binary
- key features: goroutine-based streaming, implicit interface satisfaction
- packaging: Go module with `cmd/ccc` binary

## Crystal

- likely shape: library using `Process` stdlib, `ccc` binary
- key features: Ruby-like syntax, compiled, type inference, fibers for concurrency
- packaging: Shards package

## Ruby

- likely shape: library using `Open3` or `IO.popen`, `ccc` CLI script
- key features: blocks for streaming, dynamic typing, gem packaging
- packaging: Gem with executable

## Perl

- likely shape: library using `IPC::Run` or `open3`, `ccc` script
- key features: TMTOWTDI, mature ecosystem
- packaging: CPAN distribution

## PHP

- likely shape: library using `proc_open` or `symfony/process`, `ccc` CLI script
- key features: Composer autoloading, wide hosting availability
- packaging: Composer package with binary

## VBScript

- likely shape: WScript.Shell `Exec`/`Run` for subprocess, `ccc.vbs` script
- key features: Windows-native, WSH environment
- packaging: standalone `.vbs` file, Windows Script Host execution
- limitations: Windows-only, no native streaming, limited error handling

## x86-64 ASM

- likely shape: minimal ELF binary implementing `ccc` only
- subprocess: raw Linux syscalls (`fork`, `execve`, `waitpid`, `write`, `exit`)
- prompt handling: stack-based argument parsing, no heap allocation needed for short prompts
- packaging: Makefile + NASM or GAS source
- limitations: Linux x86-64 only, no streaming, minimal error reporting

## Ordering Notes

- Python and Rust are implemented first
- parser/config design should stabilize before the remaining `ccc` ports claim compatibility
- TypeScript and C are now implemented at different maturity levels
- Elixir and OCaml are now planned for full implementation
- OCaml is design-only scaffold but should prioritize formal verification when implemented

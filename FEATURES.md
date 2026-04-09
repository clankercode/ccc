# call-coding-clis Feature Tracking

## Language Status

| # | Language | Status | Last Updated |
|---|----------|--------|-------------|
| 1 | Python | active | 2026-04-08 |
| 2 | Rust | active | 2026-04-08 |
| 3 | TypeScript | active | 2026-04-08 |
| 4 | C | active | 2026-04-08 |
| 5 | Go | active | 2026-04-08 |
| 6 | Ruby | active | 2026-04-08 |
| 7 | Perl | active | 2026-04-08 |
| 8 | C++ | active | 2026-04-08 |
| 9 | Zig | active | 2026-04-08 |
| 10 | D | active | 2026-04-08 |
| 11 | F# | active | 2026-04-08 |
| 12 | Haskell | active | 2026-04-08 |
| 13 | Nim | active | 2026-04-08 |
| 14 | Crystal | active | 2026-04-08 |
| 15 | PHP | active | 2026-04-08 |
| 16 | PureScript | active | 2026-04-08 |
| 17 | VBScript | active | 2026-04-08 |
| 18 | x86-64 ASM | active | 2026-04-08 |
| 19 | Elixir | active | 2026-04-08 |
| 20 | OCaml | active | 2026-04-08 |

## Feature Definitions

### v1 Core Features (subprocess wrapper)

| ID | Feature | Description |
|----|---------|-------------|
| F01 | build_prompt_spec | Trims prompt, rejects empty/whitespace-only, returns CommandSpec |
| F02 | CommandSpec | Holds argv, optional stdin_text, cwd, env overrides |
| F03 | CompletedRun | Holds argv, exit_code (int), stdout (str), stderr (str) |
| F04 | Runner.run | Execute spec, return CompletedRun |
| F05 | Runner.stream | Execute spec with event callback, return CompletedRun |
| F06 | ccc CLI | `ccc "<Prompt>"` binary interface |
| F07 | Prompt trimming | Leading/trailing whitespace stripped |
| F08 | Empty prompt rejection | Empty/whitespace-only prompts rejected with exit 1 |
| F09 | Usage on bad args | Missing/extra args prints usage to stderr, exit 1 |
| F10 | Stdin support | CommandSpec.stdin_text piped to child process |
| F11 | CWD support | CommandSpec.cwd sets working directory |
| F12 | Env override | CommandSpec.env merged with process environment |
| F13 | Startup failure reporting | Missing binary produces stderr with "failed to start" |
| F14 | Exit code forwarding | Child exit code returned as-is |
| F15 | CCC_REAL_OPENCODE | Env var overrides opencode binary for testing |

### v2 Parser/Config Features

| ID | Feature | Description |
|----|---------|-------------|
| F16 | Runner selector | e.g., `cc`, `oc`, `k`, `claude`, `opencode`, `kimi` |
| F17 | Thinking level | `+0` through `+4` selector |
| F18 | Provider/model selector | `:provider:model` and `:model` syntax |
| F19 | Alias/preset | `@alias` named presets |
| F20 | Config file loading | Read config for defaults, aliases, abbreviations |
| F21 | Custom abbreviations | User-defined runner abbreviations in config |
| F22 | Default provider/model | Config-backed default resolution |
| F32 | Yolo mode | `--yolo` / `-y` selects the runner's lowest-friction auto-approval mode |
| F33 | Order-independent controls | Pre-prompt control tokens may appear in any order; `--` forces literal prompt text |

### v3 JSON Output Features

| ID | Feature | Description |
|----|---------|-------------|
| F23 | JSON output parsing | Parse structured JSON output from coding CLIs |
| F24 | JSON schema: opencode | Parse OpenCode JSON streaming format |
| F25 | JSON schema: claude-code | Parse Claude Code JSON streaming format |
| F26 | JSON schema: kimi | Parse Kimi JSON streaming format |
| F27 | JSON render | Render parsed JSON output consistently |

### v4 Testing & Infrastructure

| ID | Feature | Description |
|----|---------|-------------|
| F28 | Unit tests | Language-specific unit test suite |
| F29 | Contract tests | Pass cross-language contract tests |
| F30 | Harness tests | Pass mock-coding-cli harness tests |
| F31 | JSON fixture tests | Pass mock JSON output fixture tests |

## Feature Matrix

### v1 Core Features

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ | Zig | D | F# | Haskell | Nim | Crystal | PHP | PureScript | VBScript | ASM | Elixir | OCaml |
|---------|--------|------|------------|---|-----|------|------|-----|-----|---|-----|---------|-----|---------|-----|-----------|----------|-----|--------|-------|
| F01 build_prompt_spec | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F02 CommandSpec | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F03 CompletedRun | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F04 Runner.run | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F05 Runner.stream | yes | yes | yes | no | yes | yes | fake | fake | yes | yes | yes | yes | yes | yes | yes | yes | yes | no | fake | yes |
| F06 ccc CLI | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F07 Prompt trimming | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F08 Empty rejection | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F09 Usage on bad args | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F10 Stdin support | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | no | yes | yes |
| F11 CWD support | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | no | yes | yes |
| F12 Env override | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | no | yes | yes |
| F13 Startup failure | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F14 Exit code fwd | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F15 CCC_REAL_OPENCODE | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F28 Unit tests | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| F29 Contract tests | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | yes | - | - | yes | - | yes |
| F30 Harness tests | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | yes | - | - | yes | - | yes |

### v2 Parser/Config Features

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ | Zig | D | F# | Haskell | Nim | Crystal | PHP | PureScript | VBScript | ASM | Elixir | OCaml |
|---------|--------|------|------------|---|-----|------|------|-----|-----|---|-----|---------|-----|---------|-----|-----------|----------|-----|--------|-------|
| F16 Runner selector | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F17 Thinking level | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F18 Provider/model | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F19 Alias/preset | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F20 Config loading | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F21 Custom abbrevs | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |
| F22 Default prov/model | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | yes | n/a | yes | yes |

### v3 JSON Output Features

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ | Zig | D | F# | Haskell | Nim | Crystal | PHP | PureScript | VBScript | ASM | Elixir | OCaml |
|---------|--------|------|------------|---|-----|------|------|-----|-----|---|-----|---------|-----|---------|-----|-----------|----------|-----|--------|-------|
| F23 JSON parsing | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | n/a | yes | yes |
| F24 Schema: opencode | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | n/a | yes | yes |
| F25 Schema: claude | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | n/a | yes | yes |
| F26 Schema: kimi | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | n/a | yes | yes |
| F27 JSON render | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | - | - | n/a | yes | yes |

## Progress Tracking

### Current Focus
- All phases complete. Full test suite: 17 PASS, 0 FAIL, 5 SKIP
- Comparison runner (`compare_ccc.sh`) validates all 14 active languages produce identical output
- Python and Rust now define the reference semantics for `--yolo` and order-independent pre-prompt control tokens

### Completed Milestones
- Phase 1: Foundation — FEATURES.md, JSON fixtures, mock plan, all 8 original languages verified
- Phase 2: All 12 remaining languages implemented (Zig, D, F#, Haskell, Nim, Crystal, PHP, PureScript, VBScript, x86-64 ASM, Elixir, OCaml)
- Phase 3: v2 parser/config — parse_args, resolve_command, runner registry, config loading across 18/20 languages
- Phase 4: v3 JSON output parsing — all 3 schemas across 18/20 languages
- Cross-language: 15/20 languages in contract + harness tests; comparison runner covers 14 active
- Root Cargo.toml fixed (serde_json dependency) — cargo run from project root now works

### Skipped Languages (Known Issues)
- Crystal: stdout/stderr channel ordering non-deterministic in harness
- Nim: binary hangs (never closes stdin pipe) in harness
- Elixir: escript hangs on invocation in harness
- Haskell: requires cabal/ghc in PATH (passes locally, skipped in CI)
- VBScript: Windows-only (WSH)
- PureScript: requires spago toolchain
- ASM: v1 only (no string processing for v2/v3)

### Notes
- C Runner.stream not implemented (known gap)
- Perl/C++ Runner.stream is "fake passthrough"
- ASM has no stdin/cwd/env support (raw syscalls, no libc)
- Contract/harness tests wired for: Python, Rust, TypeScript, C, Go, Ruby, Perl, C++, Zig, D, F#, PHP, ASM, OCaml (14) + PureScript (contract only)

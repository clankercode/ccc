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
| 9 | Zig | planned | - |
| 10 | D | planned | - |
| 11 | F# | planned | - |
| 12 | Haskell | planned | - |
| 13 | Nim | planned | - |
| 14 | Crystal | planned | - |
| 15 | PHP | planned | - |
| 16 | PureScript | planned | - |
| 17 | VBScript | planned | - |
| 18 | x86-64 ASM | planned | - |
| 19 | Elixir | planned | - |
| 20 | OCaml | planned | - |

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
| F01 build_prompt_spec | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F02 CommandSpec | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F03 CompletedRun | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F04 Runner.run | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F05 Runner.stream | yes | yes | yes | no | yes | yes | fake | fake | - | - | - | - | - | - | - | - | - | - | - | - |
| F06 ccc CLI | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F07 Prompt trimming | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F08 Empty rejection | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F09 Usage on bad args | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F10 Stdin support | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F11 CWD support | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F12 Env override | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F13 Startup failure | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F14 Exit code fwd | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F15 CCC_REAL_OPENCODE | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F28 Unit tests | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F29 Contract tests | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |
| F30 Harness tests | yes | yes | yes | yes | yes | yes | yes | yes | - | - | - | - | - | - | - | - | - | - | - | - |

### v2 Parser/Config Features

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ | Zig | D | F# | Haskell | Nim | Crystal | PHP | PureScript | VBScript | ASM | Elixir | OCaml |
|---------|--------|------|------------|---|-----|------|------|-----|-----|---|-----|---------|-----|---------|-----|-----------|----------|-----|--------|-------|
| F16 Runner selector | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F17 Thinking level | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F18 Provider/model | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F19 Alias/preset | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F20 Config loading | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F21 Custom abbrevs | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F22 Default prov/model | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### v3 JSON Output Features

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ | Zig | D | F# | Haskell | Nim | Crystal | PHP | PureScript | VBScript | ASM | Elixir | OCaml |
|---------|--------|------|------------|---|-----|------|------|-----|-----|---|-----|---------|-----|---------|-----|-----------|----------|-----|--------|-------|
| F23 JSON parsing | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F24 Schema: opencode | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F25 Schema: claude | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F26 Schema: kimi | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| F27 JSON render | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

## Progress Tracking

### Current Focus
- Phase 1: Foundation — setting up tracking, researching JSON schemas, creating mock coding CLI plan

### Completed Milestones
- (none yet)

### Notes
- C Runner.stream is "no" (not implemented)
- Perl and C++ Runner.stream is "fake passthrough" (not real concurrent streaming)
- v2/v3 features not yet started for any language

# Master Specification Index

Single entry point for judging any `ccc` language implementation.

## v1 Core Contract

Every implementation must provide a **library** and a **CLI binary**.

### CLI: `ccc "<Prompt>"`

- Exactly one positional argument
- Prompt trimmed of leading/trailing whitespace
- Empty/whitespace-only prompt → stderr message, exit 1
- Missing/extra args → `usage: ccc "<Prompt>"` on stderr, exit 1
- On success: forward stdout/stderr and exit code from the runner

### Library API

| Component | Responsibility |
|-----------|---------------|
| `build_prompt_spec(prompt)` | Trim, reject empty, return `CommandSpec` with `argv=["opencode","run","<trimmed>"]` |
| `CommandSpec` | Holds argv, optional stdin_text, cwd, env overrides |
| `CompletedRun` | Holds argv, exit_code (int), stdout (str), stderr (str) |
| `Runner.run(spec)` | Execute spec, return `CompletedRun` |
| `Runner.stream(spec, callback)` | Execute spec with event callback, return `CompletedRun` |

### Error format

`"failed to start <argv[0]>: <error>"` — just argv[0], not full argv.

### Environment

`CCC_REAL_OPENCODE` overrides the runner binary for testing.

**Full details:** [IMPLEMENTATION_REFERENCE.md](IMPLEMENTATION_REFERENCE.md), [CCC_BEHAVIOR_CONTRACT.md](CCC_BEHAVIOR_CONTRACT.md)

---

## v2 Parser/Config

Extends the CLI beyond simple `ccc "<Prompt>"` with structured argument parsing.

### Parse slots (in order)

1. Runner selector — `cc`, `oc`, `k`, `claude`, `opencode`, `kimi`, etc.
2. Thinking level — `+0` through `+4`
3. Provider/model — `:provider:model` or `:model`
4. Alias/preset — `@alias`
5. Prompt — remaining text

### Config loading

Implementations read a config file for: default runner, custom abbreviations, alias/preset definitions, default provider/model.

**Full details:** [CCC_PARSER_CONFIG_DESIGN.md](CCC_PARSER_CONFIG_DESIGN.md)

---

## v3 JSON Output Parsing

Parse structured JSON output from coding CLIs into a common data model.

### Supported schemas

| Schema | Format | Key extraction |
|--------|--------|---------------|
| OpenCode | Single JSON object | `response`, `error` |
| Claude Code | NDJSON stream | `system`, `assistant`, `stream_event`, `tool_use`, `tool_result`, `result` |
| Kimi Code | NDJSON stream | Role-based messages (`assistant`, `tool`) + typed events |

### Common output model

`ParsedJsonOutput` → `schema_name`, `events[]`, `final_text`, `session_id`, `error`, `usage`, `cost_usd`, `duration_ms`, `raw_lines[]`

`JsonEvent` → `event_type`, `text`, `thinking`, `tool_call?`, `tool_result?`

**Full details:** [JSON_PARSING_MAP.md](JSON_PARSING_MAP.md)

---

## Feature IDs

All features are tracked with stable IDs (F01–F31). Use these when reporting compliance.

| Range | Category |
|-------|----------|
| F01–F15 | v1 core (subprocess wrapper) |
| F16–F22 | v2 parser/config |
| F23–F27 | v3 JSON output |
| F28–F31 | Testing & infrastructure |

**Full matrix and definitions:** [FEATURES.md](FEATURES.md)

---

## Testing

### Contract tests

`tests/test_ccc_contract.py` — basic smoke tests (happy path, empty prompt, missing prompt, whitespace).

### Harness tests

`tests/test_harness.py` — deep behavioral tests using `mock-coding-cli`: exit code forwarding, stderr forwarding, stdin passthrough, multiline output, special characters, mixed streams.

### JSON fixture tests

`tests/test_json_fixtures.py` — validates JSON parsing against fixture files in `tests/fixtures/json-schemas/`.

### Comparison runner

`compare_ccc.sh` — validates all active languages produce identical output for the same inputs.

**Full details:** [TEST_HARNESS_PLAN.md](TEST_HARNESS_PLAN.md), [MOCK_CODING_CLI_PLAN.md](MOCK_CODING_CLI_PLAN.md)

---

## Language Status

20 implementations across: Python, Rust, TypeScript, C, Go, Ruby, Perl, C++, Zig, D, F#, Haskell, Nim, Crystal, PHP, PureScript, VBScript, x86-64 ASM, Elixir, OCaml.

**Current status and known gaps:** [FEATURES.md](FEATURES.md)

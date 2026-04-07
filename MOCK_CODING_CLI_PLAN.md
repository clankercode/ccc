# Mock Coding CLI Plan

## Purpose

A deterministic mock binary that replaces real coding CLIs (opencode, claude, kimi, etc.) during testing. It produces predictable output in both plain-text and structured JSON formats, controlled via environment variables.

## Location

`tests/mock-coding-cli/` — the existing `mock_coding_cli.sh` will be extended.

## Design

### Environment Variable Control

| Env Var | Values | Description |
|---------|--------|-------------|
| `MOCK_JSON_SCHEMA` | `opencode`, `claude-code`, `kimi-code` | Which JSON schema to emit |
| `MOCK_JSON_SCHEMA` unset | (none) | Plain text mode (backward compatible with current behavior) |

### Invocation

```bash
mock_coding_cli.sh [run] "<prompt>"
```

The mock receives the same argv that `ccc` constructs (e.g., `mock_coding_cli run "hello world"`).

### Output Modes

#### Plain Text Mode (default, `MOCK_JSON_SCHEMA` unset)

Existing behavior — matches prompts against a table and emits plain text. Backward compatible with all current tests.

#### JSON Schema: `opencode`

Emits a single JSON object:
```json
{"response": "mock: ok"}
```

#### JSON Schema: `claude-code` (NDJSON)

Emits NDJSON lines following Claude Code's `stream-json` format:
```json
{"type":"system","subtype":"init","session_id":"mock-session","tools":[],"model":"mock","permission_mode":"default"}
{"type":"assistant","message":{"id":"msg_mock","type":"message","role":"assistant","model":"mock","content":[{"type":"text","text":"mock: ok"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"mock-session"}
{"type":"result","subtype":"success","cost_usd":0.0,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"mock: ok","session_id":"mock-session","usage":{"input_tokens":10,"output_tokens":5}}
```

#### JSON Schema: `kimi-code` (NDJSON)

Emits NDJSON lines following Kimi Code's `stream-json` format:
```json
{"role":"assistant","content":"mock: ok"}
```

For tool call scenarios:
```json
{"role":"assistant","content":[{"type":"text","text":"Let me help."}],"tool_calls":[{"type":"function","id":"call_mock_1","function":{"name":"read_file","arguments":"{\"path\":\"/test.py\"}"}}]}
{"role":"tool","content":[{"type":"text","text":"<system>Tool completed successfully.</system>"},{"type":"text","text":"file contents..."}],"tool_call_id":"call_mock_1"}
{"role":"assistant","content":"mock: ok"}
```

### Prompt Table (Extended)

The existing prompt table is extended with JSON-aware entries:

| Prompt/Trigger | Exit Code | Plain Text Stdout | JSON Behavior |
|---|---|---|---|
| `hello world` | 0 | `mock: ok\n` | Schema-appropriate JSON |
| `Fix the failing tests` | 0 | `opencode run Fix the failing tests\n` | Schema-appropriate JSON |
| `exit 42` | 42 | (empty) | Schema-appropriate JSON error on stderr |
| `stderr test` | 0 | `mock: stdout output\n` | Schema-appropriate JSON + stderr |
| `multiline` | 0 | `line1\nline2\nline3\n` | Schema-appropriate multi-line JSON |
| `large output` | 0 | 4096+ A's | Schema-appropriate large JSON |
| `mixed streams` | 1 | `mock: out\n` | Schema-appropriate JSON + stderr |
| `tool call` | 0 | `mock: tool call executed\n` | Emits tool_call + tool_result messages |
| `thinking` | 0 | `mock: thinking done\n` | Emits thinking/reasoning content |
| (stdin `PROMPT:`) | 0 | `mock: stdin received: <text>` | Schema-appropriate JSON |
| (no args) | 1 | (empty) | Error JSON |
| (any other) | 0 | `mock: unknown prompt '<args>'\n` | Schema-appropriate JSON |

### Implementation Steps

1. **Extend `mock_coding_cli.sh`** to check `MOCK_JSON_SCHEMA` env var
2. **Add JSON output functions** for each schema
3. **Add new prompt entries** for `tool call` and `thinking`
4. **Create fixture test** in `tests/test_json_fixtures.py` that validates mock output against saved JSON schemas
5. **Wire into harness** — extend `tests/test_harness.py` to run JSON schema test cases

### Acceptance Criteria

- [ ] Mock binary supports `MOCK_JSON_SCHEMA` env var with values `opencode`, `claude-code`, `kimi-code`
- [ ] Default behavior (unset env var) is identical to current behavior
- [ ] Each JSON schema produces valid, parseable JSON matching its fixture
- [ ] `tool call` prompt produces tool_call + tool_result sequences in each schema
- [ ] `thinking` prompt produces thinking/reasoning content in each schema
- [ ] Error cases (exit 42, mixed streams) produce correct JSON on stderr
- [ ] All existing tests continue to pass (backward compatibility)
- [ ] New JSON fixture tests pass
- [ ] Harness tests pass for all 8 languages in both plain text and JSON modes

### JSON Schema Fixture Files

Reference schemas are in `tests/fixtures/json-schemas/`:
- `claude-code.json` — Claude Code streaming JSON format
- `kimi-code.json` — Kimi Code streaming JSON format
- `opencode.json` — OpenCode simple JSON format

### Future Extensions

- Additional schemas as more coding CLIs are supported
- Streaming simulation with configurable delays
- Configurable error injection patterns
- Support for `--output-format` flag detection in argv (in addition to env var)

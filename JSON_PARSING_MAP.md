# JSON Output Parsing Map

Quick reference for what each ccc client extracts from coding CLI JSON output.
All 17 implementations share the same data model and parsing behavior.

## Output Types

```
ParsedJsonOutput
  schema_name : str          # "opencode" | "claude-code" | "kimi" | "cursor-agent" | "codex"
  events      : [JsonEvent]
  final_text  : str
  session_id  : str
  error       : str
  usage       : {str: int}
  cost_usd    : float
  duration_ms : int
  raw_lines   : [dict]

JsonEvent
  event_type  : str
  text        : str
  thinking    : str
  tool_call   : ToolCall?
  tool_result : ToolResult?

ToolCall  →  id, name, arguments
ToolResult → tool_call_id, content, is_error
```

## Which ParsedJsonOutput fields each schema populates

| Field | opencode | claude-code | kimi | cursor-agent | codex |
|---|:---:|:---:|:---:|:---:|:---:|
| final_text | `response` | message text or result | content text parts | assistant/result text | completed agent message |
| session_id | `sessionID` | system.init | — | system/result | thread.started |
| error | top-level key | result.error | — | result.error | — |
| usage | tokens | message + result | — | result | turn.completed |
| cost_usd | step_finish | result | — | — | — |
| duration_ms | — | result | — | result | — |

## OpenCode

JSON event stream (`--format json`), with legacy one-shot `response` and `error` objects still accepted.

| Wire key | Extracted | → Event type |
|---|---|---|
| `response` | yes | `text` |
| `error` | yes | `error` |
| `step_start` | `sessionID` | (sets `session_id`) |
| `text` | `part.text` | `text` |
| `tool_use` | tool name, call id, input, output | `tool_use`, `tool_result` |
| `step_finish` | token usage, cost | (sets output fields) |
| everything else | raw_lines only | — |

## Claude Code

NDJSON (`--output-format stream-json`).

| Wire line type | Extracted fields | → Event type |
|---|---|---|
| `system` subtype=`init` | `session_id` | (sets output field) |
| `system` subtype=`api_retry` | — | `system_retry` |
| `assistant` | `message.content` text blocks, `message.usage` | `assistant` |
| `stream_event` delta=`text_delta` | `delta.text` | `text_delta` |
| `stream_event` delta=`thinking_delta` | `delta.thinking` | `thinking_delta` |
| `stream_event` delta=`input_json_delta` | `delta.partial_json` | `tool_input_delta` |
| `stream_event` block start type=`thinking` | — | `thinking_start` |
| `stream_event` block start type=`tool_use` | `content_block.id`, `.name` | `tool_use_start` |
| `tool_use` | `tool_name`, `tool_input` | `tool_use` |
| `tool_result` | `tool_use_id`, `content`, `is_error` | `tool_result` |
| `result` subtype=`success` | `result`, `cost_usd`, `duration_ms`, `usage` | `result` |
| `result` subtype=`error` | `error` | `error` |

**Ignored stream_event sub-types**: `message_start`, `message_delta`, `message_stop`, `content_block_stop`

**Ignored fields** (per line type): `session_id`, `uuid`, `parent_tool_use_id`, `message.id`/`.model`/`.stop_reason`/`.stop_sequence`, `duration_api_ms`, `num_turns`

## Kimi Code

NDJSON (`--output-format stream-json`). Two line families: typed events and role-based messages.

### Typed events

All produce events with type = wire `type` lowercased. **No payload fields are extracted** — captured in `raw` only.

| Wire type | Payload (ignored) |
|---|---|
| `TurnBegin` | user_input |
| `StepBegin` | n |
| `StepInterrupted` | — |
| `TurnEnd` | — |
| `StatusUpdate` | context_usage, token_usage, message_id, plan_mode, mcp_status |
| `HookTriggered` | event, target, hook_count |
| `HookResolved` | event, target, action, reason, duration_ms |
| `ApprovalRequest` | id, tool_call_id, sender, action, description |
| `SubagentEvent` | parent_tool_call_id, agent_id, event |
| `ToolCallRequest` | id, name, arguments |

### Role-based messages

| Role + content shape | Extracted | → Event type |
|---|---|---|
| `assistant`, content is string | content | `assistant` |
| `assistant`, content parts `type=text` | part.text | `assistant` |
| `assistant`, content parts `type=think` | part.think (not encrypted) | `thinking` |
| `assistant` + `tool_calls` array | tc.id, tc.function.name, tc.function.arguments | `tool_call` |
| `tool`, content text parts (not `<system>`) | text, tool_call_id | `tool_result` |

**Filtered out**: Kimi tool result text parts starting with `<system>` are dropped (includes error markers like `<system>ERROR:...</system>`). `is_error` always defaults to `false`.

**Ignored wire shapes** (no handler): `notification`, `plan_display`, `role=user`

## Cursor Agent

NDJSON (`--output-format json` or `--output-format stream-json`).

| Wire line type | Extracted fields | → Event type |
|---|---|---|
| `system` subtype=`init` | `session_id` | (sets output field) |
| `assistant` | message content text | `assistant` |
| `result` subtype=`success` | `result`, `session_id`, `duration_ms`, `usage` | `result` |
| `result` subtype=`error` or `is_error=true` | `error` or `result` | `error` |

## Codex

JSONL (`codex exec --json`).

| Wire line type | Extracted fields | → Event type |
|---|---|---|
| `thread.started` | `thread_id` | (sets `session_id`) |
| `turn.started` | — | — |
| `item.started`, item type=`command_execution` | `item.id`, `item.command` | `tool_use_start` |
| `item.completed`, item type=`command_execution` | `item.id`, `aggregated_output`, `exit_code`, `status` | `tool_result` |
| `item.completed`, item type=`agent_message` | `item.text` | `assistant` |
| `turn.completed` | `usage` counters | (sets output field) |
| `error`, `turn.failed` | nested JSON `message` / `error.message` payload, `status`, error type | `error` |

Codex command execution items use normalized tool name `command_execution` and store the command preview in `ToolCall.arguments` as `{"command": "..."}` so formatted rendering can show the shell command consistently.

Duplicate Codex failure events with the same decoded message are collapsed so a single upstream error is rendered once.

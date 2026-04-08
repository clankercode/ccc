# JSON Output Parsing Map

Quick reference for what each ccc client extracts from coding CLI JSON output.
All 17 implementations share the same data model and parsing behavior.

## Output Types

```
ParsedJsonOutput
  schema_name : str          # "opencode" | "claude-code" | "kimi"
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

| Field | opencode | claude-code | kimi |
|---|:---:|:---:|:---:|
| final_text | `response` | message text or result | content text parts |
| session_id | — | system.init | — |
| error | top-level key | result.error | — |
| usage | — | message + result | — |
| cost_usd | — | result | — |
| duration_ms | — | result | — |

## OpenCode

Single JSON object, no streaming.

| Wire key | Extracted | → Event type |
|---|---|---|
| `response` | yes | `text` |
| `error` | yes | `error` |
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

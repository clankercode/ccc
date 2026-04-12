# JSON Event References

This file collects upstream references for structured output and wire-event shapes that matter to `ccc`.

It is intentionally source-first:

- official docs where they exist
- source-level references only when docs are incomplete
- explicit notes when no exhaustive upstream list was found

## Claude

Primary references:

- Claude Code common workflows: <https://code.claude.com/docs/en/common-workflows>
- Claude API streaming messages: <https://platform.claude.com/docs/en/build-with-claude/streaming>

What these references cover:

- Claude Code documents `--output-format text`, `--output-format json`, and `--output-format stream-json`.
- The Claude API streaming reference gives the clearest event taxonomy for the stream family:
  - `message_start`
  - `content_block_start`
  - `content_block_delta`
  - `content_block_stop`
  - `message_delta`
  - `message_stop`
  - `ping`
  - `error`
- The same page also documents delta subtypes used by `ccc`:
  - `text_delta`
  - `input_json_delta`
  - `thinking_delta`
  - `signature_delta`

Important caveat:

- We did not find a single official Claude Code CLI page that exhaustively lists every JSON object shape emitted by the CLI wrapper itself.
- In practice, `ccc` should continue to treat unknown Claude JSON objects as expected and preserve them for fixture-driven follow-up work.

## Kimi

Primary reference:

- Kimi Code CLI Wire Mode: <https://moonshotai.github.io/kimi-cli/en/customization/wire-mode.html>

What it covers:

- Kimi documents its low-level structured protocol as JSON-RPC over stdin/stdout.
- The doc provides an explicit union of wire message types.

Documented event notifications:

- `TurnBegin`
- `TurnEnd`
- `StepBegin`
- `StepInterrupted`
- `CompactionBegin`
- `CompactionEnd`
- `StatusUpdate`
- `ContentPart`
- `ToolCall`
- `ToolCallPart`
- `ToolResult`
- `ApprovalResponse`
- `SubagentEvent`
- `SteerInput`
- `PlanDisplay`
- `HookTriggered`
- `HookResolved`

Documented request messages:

- `ApprovalRequest`
- `ToolCallRequest`
- `QuestionRequest`
- `HookRequest`

Important caveat:

- `ccc` currently integrates Kimi via print/stream-json style CLI output, not full `--wire` JSON-RPC mode.
- The wire-mode reference is still the best upstream source for the structured event vocabulary Kimi uses.

## OpenCode

Primary reference:

- OpenCode CLI docs: <https://opencode.ai/docs/cli/>

Relevant upstream claims:

- `opencode run --format json` is documented as `json (raw JSON events)`.
- `OPENCODE_DISABLE_TERMINAL_TITLE` is documented as a boolean environment variable for disabling terminal title updates.

What we did not find:

- We did not find an official page that exhaustively enumerates the concrete JSON event object types emitted by `opencode run --format json`.

Current `ccc` integration note:

- Real smoke verification currently observes at least:
  - `step_start`
  - `text`
  - `step_finish`
- Real smoke verification also confirms that `opencode run --format json` emits those events incrementally, so `ccc` uses that same upstream transport for both buffered `formatted` and live `stream-formatted`.
- Real smoke verification also observed OSC terminal-title control sequences in buffered raw output, so Python and Rust now strip those sequences on the `ccc` side for OpenCode buffered raw modes.

## Cursor Agent

Primary reference:

- Local `cursor-agent --help` verified on 2026-04-12.

Relevant local CLI surface:

- `cursor-agent --print --output-format text|json|stream-json`
- `--model`
- `--mode plan|ask`
- `--yolo`
- `--sandbox enabled|disabled`
- `--trust`

Current `ccc` integration note:

- `ccc` uses `cursor-agent --print --trust`.
- Real smoke verification with `--output-format json` observed a single `result` object with `type`, `subtype`, `result`, `session_id`, and token usage fields.
- Real smoke verification with `--output-format stream-json` observed newline-delimited `system`, `user`, `assistant`, and `result` objects.
- `ccc` does not pass `--stream-partial-output` for v1 Cursor support because local smoke verification showed duplicate assistant text events for the same final answer.

## How To Use These References

When updating a parser or adding a new language implementation:

1. Start with the official reference above.
2. Compare it against the checked-in real fixtures under `tests/fixtures/runner-transcripts/`.
3. Preserve unknown objects instead of dropping them silently.
4. Update fixtures and this file when upstream adds new event families.

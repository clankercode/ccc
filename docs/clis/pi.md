# Pi

## Status

- Verified against local binary on 2026-06-16: `pi`
- Local version checked: `0.79.4`
- Primary references:
  - local `pi --help`
  - Pi docs: `https://pi.dev`
  - GitHub: `https://github.com/earendil-works/pi`

## Non-interactive shape

```sh
pi -p "your prompt"
```

Useful flags from local help:

- `-p`, `--print`
- `--provider <name>`
- `--model <pattern>`
- `--thinking off|minimal|low|medium|high|xhigh`
- `--mode text|json|rpc`
- `--no-session`
- `--session <path|id>`
- `--continue`, `-c`
- `--resume`, `-r`

## Permission controls

Pi uses `--approve` for trusting project-local files for the run, and `--no-approve` to ignore them. Pi does not have explicit permission mode flags like Claude or OpenCode.

What this means for `ccc`:

- safe mode: no special flags needed (pi defaults to asking for approval)
- yolo mode: not directly supported via CLI flags; pi relies on project-local approval

## Session persistence

Pi exposes `--no-session` for ephemeral runs.

What this means for `ccc`:

- Python and Rust add `--no-session` by default so `ccc` runs do not persist sessions
- `ccc --save-session p ...` omits `--no-session` and restores normal Pi session saving

## Structured output

Pi supports JSON streaming via `--mode json`:

```sh
pi -p --mode json "your prompt"
```

The JSON format emits NDJSON events with these types:
- `session` — session metadata with `id`, `version`, `timestamp`
- `agent_start`, `agent_end` — agent lifecycle
- `turn_start`, `turn_end` — turn lifecycle with usage data
- `message_start`, `message_update`, `message_end` — message lifecycle
- `message_update` subtypes: `thinking_start/delta/end`, `text_start/delta/end`, `toolcall_start/delta/end`
- `tool_execution_start/update/end` — tool execution events

## Quick checks

```sh
pi --version
pi --help
pi --list-models
```

## Notes for `ccc`

- `ccc` uses `pi -p` for non-interactive mode
- Python and Rust add `--no-session` by default for ephemeral runs
- Python and Rust map `json`, `stream-json`, `formatted`, and `stream-formatted` to `pi -p --mode json`
- the pi JSON parser extracts session ID, text content, thinking content, tool calls, tool results, and usage data
- pi supports thinking levels via `--thinking <level>` (off, minimal, low, medium, high, xhigh)
- pi supports provider selection via `--provider <name>` and model selection via `--model <pattern>`; Python and Rust emit both flags for aliases that configure both fields

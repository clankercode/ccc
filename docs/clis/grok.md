# Grok Build

## Status

- Verified against local binary on 2026-07-11: `grok`
- Local version checked: `0.2.93`
- Primary references:
  - local `grok --help`
  - Grok Build headless docs (`~/.grok/docs/user-guide/14-headless-mode.md`)

## Non-interactive shape

Bare positional prompts start the interactive TUI. Headless runs must use `-p` / `--single`:

```sh
grok -p "your prompt"
```

Useful flags from local help:

- `-p`, `--single <PROMPT>`
- `-m`, `--model <MODEL>`
- `--output-format plain|json|streaming-json`
- `--always-approve`
- `--permission-mode default|acceptEdits|auto|dontAsk|bypassPermissions|plan`
- `--reasoning-effort` / `--effort` (`none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`)
  - Note: the CLI accepts `none`, but current default model `grok-4.5` rejects it with HTTP 400
- `--agent <NAME>`
- `--no-auto-update`
- `-r` / `--resume`, `-c` / `--continue`
- `sessions list|delete <id>`

## Permission controls

Grok exposes both `--always-approve` and `--permission-mode`.

What this means for `ccc`:

- safe mode maps to `--permission-mode default`
- auto mode maps to `--permission-mode auto`
- yolo mode maps to `--always-approve`
- plan mode maps to `--permission-mode plan`

## Session persistence

Each headless run creates a session under `~/.grok/sessions` (override with `GROK_HOME`). There is no no-persist flag.

What this means for `ccc`:

- Python and Rust warn by default that Grok may save a session
- `--save-session` keeps normal session saving and suppresses that warning
- `--cleanup-session` deletes the run's session via `grok sessions delete <sessionId>` when a session ID is available from JSON/`end` events
- cleanup is best-effort and only uses IDs produced by the run itself

## Version discovery

`grok --version` works. Python and Rust prefer a fast path:

- read `$GROK_HOME/version.json` or `~/.grok/version.json`
- use the `"version"` field when present
- fall back to `grok --version`

## Output modes

Python and Rust support raw text, raw JSON, and formatted transcript modes:

- raw text uses default `plain` output
- raw `json` uses `--output-format json`
- streaming JSON uses `--output-format streaming-json` (upstream name; not `stream-json`)
- `formatted` and `stream-formatted` also use `--output-format streaming-json`

One-shot JSON shape:

```json
{
  "text": "...",
  "stopReason": "EndTurn",
  "sessionId": "...",
  "requestId": "...",
  "thought": "..."
}
```

Streaming NDJSON event types observed locally:

- `thought` — reasoning chunk (`data`)
- `text` — assistant text chunk (`data`)
- `end` — final metadata (`sessionId`, `requestId`, `stopReason`)
- `error` — failure (`message`)

Tool-call events were not present on the streaming-json surface in local smoke tests; treat the event list as non-exhaustive.

## Quick checks

```sh
grok --version
grok --help
grok -p "Respond with exactly pong" --always-approve
grok -p "Respond with exactly pong" --always-approve --output-format json
grok -p "Respond with exactly pong" --always-approve --output-format streaming-json
```

## Notes for `ccc`

- `ccc` uses `grok --no-auto-update -p`
- the canonical selectors are `grok` and `gb`
- thinking `+0..+4` maps to `--reasoning-effort minimal|low|medium|high|xhigh`
  - `+0` uses `minimal` rather than `none` because `grok-4.5` rejects `none` at the API
- Python and Rust support `CCC_REAL_GROK` for mock or local smoke overrides

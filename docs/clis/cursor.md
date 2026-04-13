# Cursor Agent

## Status

- Verified against local binary on 2026-04-12: `cursor-agent`
- Local version checked: `2026.03.30-a5d3e17`
- Primary reference:
  - local `cursor-agent --help`

## Non-interactive shape

```sh
cursor-agent --print --trust "your prompt"
```

Useful flags from local help:

- `--print`
- `--output-format text|json|stream-json`
- `--model`
- `--mode plan|ask`
- `--yolo`
- `--sandbox enabled|disabled`
- `--trust`

## Permission controls

Cursor Agent exposes coarse non-interactive controls that map cleanly to part of the current `ccc --permission-mode` surface.

What this means for `ccc`:

- safe mode maps to `--sandbox enabled`
- yolo mode maps to `--yolo`
- plan mode maps to `--mode plan`
- auto mode is not mapped yet because local help does not expose a direct equivalent

## Session persistence

Local help does not show a no-persist flag for non-interactive `cursor-agent --print` runs. It also does not expose a safe current-run cleanup command.

What this means for `ccc`:

- Python and Rust warn by default that Cursor Agent may save a session
- `--save-session` keeps the current Cursor behavior and suppresses that warning
- `--cleanup-session` warns that automatic cleanup is unsupported for Cursor
- `ccc` does not delete guessed Cursor state

## Version discovery

`cursor-agent --version` is supported but starts the bundled Node runtime. Python and Rust avoid that slow path when the local install layout is recognizable:

- resolve `cursor-agent` through symlinks
- verify the adjacent `package.json` has `name = "@anysphere/agent-cli-runtime"`
- read the bundled `index.js` release marker such as `agent-cli@2026.03.30-a5d3e17`
- fall back to `cursor-agent --version` if that metadata is missing

## Output modes

Cursor Agent supports all current Python and Rust output modes:

- raw text uses the default text output
- raw JSON uses `--output-format json`
- streaming JSON and formatted transcript modes use `--output-format stream-json`

`ccc` intentionally does not pass `--stream-partial-output` for v1 Cursor support because local smoke verification showed duplicate assistant text events for the same final answer.

## Quick checks

```sh
cursor-agent --version
cursor-agent --help
cursor-agent --print --mode ask --trust --output-format text "Respond with exactly pong"
cursor-agent --print --mode ask --trust --output-format json "Respond with exactly pong"
cursor-agent --print --mode ask --trust --output-format stream-json "Respond with exactly pong"
```

## Notes for `ccc`

- `ccc` uses `cursor-agent --print --trust`
- the canonical selectors are `cursor` and `cu`
- `cr` remains reserved for Crush
- Python and Rust support `CCC_REAL_CURSOR` for mock or local smoke overrides

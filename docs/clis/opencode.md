# OpenCode

## Status

- Verified against local binary on 2026-04-09: `opencode`
- Primary references:
  - local `opencode run --help`
  - OpenCode docs: `https://opencode.ai/docs/permissions/`
  - OpenCode docs: `https://opencode.ai/docs/config/`

## Non-interactive shape

```sh
opencode run "your prompt"
```

Useful flags from local help:

- `--agent`
- `--model provider/model`
- `--thinking`
- `--format default|json`
- `--dir`
- `--continue`
- `--session`

## Permission controls

OpenCode has the richest documented fine-grained permission model of the CLIs we checked.

Documented upstream controls:

- `permission: "allow" | "ask" | "deny"`
- per-tool overrides, for example:

```json
{
  "permission": {
    "*": "ask",
    "bash": "allow",
    "edit": "deny"
  }
}
```

- granular object syntax for tool-specific matching
- runtime override via `OPENCODE_CONFIG_CONTENT`

What this means for `ccc`:

- a conservative safe mode can map honestly to `OPENCODE_CONFIG_CONTENT='{"permission":"ask"}'`
- a simple yolo mode maps cleanly to `OPENCODE_CONFIG_CONTENT='{"permission":"allow"}'`
- finer-grained profiles are realistic here
- per-tool allow/ask/deny could be exposed later, but only as an OpenCode-specific feature unless other runners catch up

## Session persistence

OpenCode exposes session management commands, but local help does not show a no-persist flag for `opencode run`.

What this means for `ccc`:

- Python and Rust warn by default that OpenCode may save a session
- `--save-session` keeps the current OpenCode behavior and suppresses that warning
- `--cleanup-session` tries to extract the structured `sessionID` emitted by OpenCode JSON events and then runs `opencode session delete <sessionID>` after the run
- cleanup can only work when OpenCode emits a session ID that `ccc` can see

## Quick checks

```sh
opencode --version
opencode run --help
opencode session delete --help
```

To inspect permission docs quickly:

```sh
xdg-open https://opencode.ai/docs/permissions/
xdg-open https://opencode.ai/docs/config/
```

## Notes for `ccc`

- current `ccc` mapping uses `opencode run`
- current yolo support is env-config based, not a CLI flag
- current session cleanup support is post-run deletion based, not true no-persist mode
- when `show_thinking` is enabled in `text` mode, Python and Rust intentionally upgrade OpenCode to the structured event stream so visible incoming work like read/tool activity is rendered instead of collapsing to assistant prose only
- if we add more permission controls later, OpenCode is the easiest place to start

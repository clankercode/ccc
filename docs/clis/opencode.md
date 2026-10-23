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

Python and Rust use this shape without `--pure`: OpenCode v2.0.32 rejects that legacy flag. Plugin auto-update suppression is no longer forced through `--pure`.

`ccc oc --standalone` maps to `opencode run --standalone`, which starts a private server rather than using the background service. Defaults and aliases can also set `standalone = true`; `--no-standalone` overrides that setting and allows the upstream default. A real v2.0.32 invocation with `--standalone --format json` completed successfully.

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

Python and Rust read the adjacent `opencode-cli.version` file for desktop installs whose resolved executable is `opencode-cli`, or `opencode-ai/package.json` for npm installs. Unknown layouts fall back to `opencode --version`.

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
- when `show_thinking` is enabled in `text` mode, Python and Rust intentionally upgrade OpenCode to the structured event stream so visible incoming work like reasoning summaries and read/tool activity is rendered instead of collapsing to assistant prose only
- if we add more permission controls later, OpenCode is the easiest place to start

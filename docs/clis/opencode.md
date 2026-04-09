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

## Quick checks

```sh
opencode --version
opencode run --help
```

To inspect permission docs quickly:

```sh
xdg-open https://opencode.ai/docs/permissions/
xdg-open https://opencode.ai/docs/config/
```

## Notes for `ccc`

- current `ccc` mapping uses `opencode run`
- current yolo support is env-config based, not a CLI flag
- if we add more permission controls later, OpenCode is the easiest place to start

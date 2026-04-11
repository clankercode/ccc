# Claude Code

## Status

- Verified against local binary on 2026-04-09: `claude`
- Local version checked: `2.1.97 (Claude Code)`
- Primary references:
  - local `claude --help`
  - Anthropic settings docs: `https://docs.anthropic.com/en/docs/claude-code/settings`

## Non-interactive shape

```sh
claude -p --no-session-persistence "your prompt"
```

Useful flags from local help:

- `-p`, `--print`
- `--model`
- `--agent`
- `--effort`
- `--permission-mode default|acceptEdits|auto|dontAsk|plan|bypassPermissions`
- `--allowed-tools`
- `--disallowed-tools`
- `--add-dir`
- `--output-format text|json|stream-json`
- `--no-session-persistence`

## Permission controls

Claude has real fine-grained permission controls.

Documented local CLI surface:

- `--dangerously-skip-permissions`
- `--permission-mode ...`
- `--allowed-tools`
- `--disallowed-tools`

Documented upstream settings surface:

- `allow`
- `ask`
- `deny`
- `defaultMode`
- `additionalDirectories`
- `disableBypassPermissionsMode`

What this means for `ccc`:

- yolo mode maps cleanly to `--dangerously-skip-permissions`
- a medium-granularity cross-runner abstraction could expose permission modes
- a Claude-specific advanced layer could later expose allow/deny tool rules directly

## Quick checks

```sh
claude --version
claude --help
```

To inspect permission settings quickly:

```sh
xdg-open https://docs.anthropic.com/en/docs/claude-code/settings
```

## Notes for `ccc`

- `ccc` now uses `claude -p` for non-interactive mode
- Python and Rust add `--no-session-persistence` by default so `ccc` runs do not appear in the user's resumable session list
- `ccc --save-session cc ...` omits the no-persistence flag and restores normal Claude session saving
- Claude is one of the best candidates for exposing more than a binary yolo switch

# Crush

## Status

- Verified against local binary on 2026-04-09: `crush`
- Local version checked: `crush version v0.55.1`
- Primary references:
  - local `crush --help`
  - local `crush run --help`

## Non-interactive shape

```sh
crush run "your prompt"
```

Useful flags from local help:

- top level: `--yolo`
- run subcommand: `--model`, `--quiet`, `--continue`, `--session`, `--cwd`

## Permission controls

Crush looks simple from the help surface, and the real binary is stricter than its top-level examples suggest.

Observed behavior on 2026-04-09:

- top-level help advertises `--yolo`
- real non-interactive `crush run` rejected yolo when we smoke-tested it

What this means for `ccc`:

- `ccc` should not pretend Crush supports yolo in non-interactive run mode
- for now, the correct behavior is to warn and ignore `--yolo`
- this is not a good candidate for fine-grained permission controls until the upstream CLI surface is clearer

## Session persistence

Crush exposes session commands, but local help does not show a no-persist flag for `crush run`. It also does not provide a reliable run-output session ID surface that `ccc` can safely delete without guessing.

What this means for `ccc`:

- Python and Rust warn by default that Crush may save a session
- `--save-session` keeps the current Crush behavior and suppresses that warning
- `--cleanup-session` warns that automatic cleanup is unsupported for Crush
- `ccc` does not delete Crush's "last" session, because that could remove a session unrelated to the current run

## Quick checks

```sh
crush --version
crush --help
crush run --help
crush session last --help
crush session delete --help
```

To re-check the yolo mismatch quickly:

```sh
crush --help | rg yolo
crush run --help | rg yolo
```

## Notes for `ccc`

- `ccc` uses `crush run`
- `ccc --yolo cr ...` currently warns and falls back to plain `crush run`
- current session cleanup is intentionally unsupported until Crush exposes a safe current-run session ID or no-persist mode

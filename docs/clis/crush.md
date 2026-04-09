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

## Quick checks

```sh
crush --version
crush --help
crush run --help
```

To re-check the yolo mismatch quickly:

```sh
crush --help | rg yolo
crush run --help | rg yolo
```

## Notes for `ccc`

- `ccc` uses `crush run`
- `ccc --yolo cr ...` currently warns and falls back to plain `crush run`

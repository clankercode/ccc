# RooCode / `roocode`

## Status

- Not installed locally on 2026-04-09
- No `roocode` or `roo` binary was found in `PATH`
- Current repo mapping exists for compatibility experiments, but upstream verification is incomplete

## Non-interactive shape

Unverified locally.

The repo currently treats the runner name as `roocode`, but this should not be treated as authoritative documentation.

## Permission controls

Unverified locally.

What this means for `ccc`:

- safe mode should warn and leave defaults unchanged until the upstream CLI is verified directly
- yolo support should remain unsupported for now
- warnings are better than guessed flags
- do not add fine-grained permission controls for RooCode until the upstream CLI is verified directly

## Session persistence

Unverified locally.

What this means for `ccc`:

- Python and Rust warn by default that RooCode may save a session
- `--save-session` keeps the current RooCode behavior and suppresses that warning
- `--cleanup-session` warns that automatic cleanup is unsupported for RooCode
- do not add no-persist or cleanup flags for RooCode until the upstream CLI is verified directly

## Quick checks

When the binary is available, start here:

```sh
command -v roocode roo
roocode --help
roo --help
```

If one of those exists, then check non-interactive and permission-related flags:

```sh
roocode --help | rg "run|prompt|approve|permission|yolo|auto"
roo --help | rg "run|prompt|approve|permission|yolo|auto"
```

## Notes for `ccc`

- current `ccc` behavior warns and ignores `--yolo` for RooCode
- this should stay conservative until the real CLI is re-researched
- current session cleanup is intentionally unsupported until the real CLI is available for verification

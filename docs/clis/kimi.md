# Kimi Code CLI

## Status

- Verified against local binary on 2026-04-09: `kimi`
- Local version checked: `kimi, version 1.30.0`
- Primary references:
  - local `kimi --help`
  - Kimi docs: `https://moonshotai.github.io/kimi-cli/en/reference/kimi-command.html`

## Non-interactive shape

```sh
kimi --prompt "your prompt"
```

Useful flags from local help and docs:

- `--prompt`, `--command`
- `--model`
- `--thinking`, `--no-thinking`
- `--yolo`, `-y`
- `--plan`
- `--work-dir`
- `--add-dir`
- `--agent`
- `--print`

## Permission controls

Kimi is mostly binary from a permissions point of view.

Documented controls:

- `--yolo`
- `--yes`
- `--auto-approve`
- `--plan`

Docs also note that `--print` implicitly enables `--yolo`.

What this means for `ccc`:

- yolo maps cleanly to `--yolo`
- there is not much documented fine-grained permission structure beyond that
- a future generic `--plan` could make sense if we want a non-mutating mode across multiple runners

## Session persistence

Kimi documents its data directory through `KIMI_SHARE_DIR`, with sessions under the Kimi share directory, but local help does not show a no-persist flag for non-interactive runs.

What this means for `ccc`:

- Python and Rust warn by default that Kimi may save a session
- `--save-session` keeps the current Kimi behavior and suppresses that warning
- `--cleanup-session` tries to parse Kimi's `To resume this session: kimi -r <id>` hint and remove matching session files or directories under `KIMI_SHARE_DIR` or `~/.kimi`
- cleanup can only work when Kimi prints a resume ID and the session path is discoverable under the configured share directory

## Quick checks

```sh
kimi --version
kimi --help
```

To inspect the upstream command reference quickly:

```sh
xdg-open https://moonshotai.github.io/kimi-cli/en/reference/kimi-command.html
```

## Notes for `ccc`

- `ccc` uses `--prompt`
- Kimi is a good match for simple yolo/no-yolo and thinking controls
- it is not a strong candidate for per-tool permission rules
- current session cleanup support is filesystem cleanup based, not true no-persist mode

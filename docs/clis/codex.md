# Codex CLI

## Status

- Verified against local binary on 2026-04-09: `codex`
- Local version checked: `codex-cli 0.118.0`
- Primary reference:
  - local `codex exec --help`

## Non-interactive shape

```sh
codex exec "your prompt"
```

Useful flags from local help:

- `--model`
- `--sandbox read-only|workspace-write|danger-full-access`
- `--full-auto`
- `--dangerously-bypass-approvals-and-sandbox`
- `--cd`
- `--add-dir`
- `--json`
- `-c key=value` config overrides

## Permission controls

Codex exposes meaningful safety controls, but they are coarser than OpenCode or Claude.

Documented local CLI surface:

- sandbox level selection
- `--full-auto`
- `--dangerously-bypass-approvals-and-sandbox`

What this means for `ccc`:

- yolo mode maps cleanly to `--dangerously-bypass-approvals-and-sandbox`
- a safer intermediate mode could map to `--full-auto`
- sandbox choice could plausibly be exposed later as a cross-runner concept, but only Codex currently makes that especially explicit in CLI flags

## Quick checks

```sh
codex --version
codex exec --help
```

To inspect the effective documented safety surface quickly:

```sh
codex exec --help | rg "sandbox|full-auto|dangerously"
```

## Notes for `ccc`

- `ccc` uses `codex exec`
- do not depend on undocumented aliases that may happen to work locally
- if we add finer controls, Codex is a good fit for `--sandbox` style options

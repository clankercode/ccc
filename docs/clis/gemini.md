# Gemini CLI

## Status

- Verified against local binary on 2026-04-14: `gemini`
- Local version checked: `0.37.2`
- Primary reference:
  - local `gemini --help`

## Non-interactive shape

```sh
gemini --prompt "your prompt"
```

Useful flags from local help:

- `-p`, `--prompt`
- `--model`
- `--sandbox`
- `--yolo`
- `--approval-mode default|auto_edit|yolo|plan`
- `--output-format text|json|stream-json`
- `--list-sessions`
- `--delete-session`

## Permission controls

Gemini exposes approval controls that map cleanly to the current `ccc --permission-mode` surface.

What this means for `ccc`:

- safe mode maps to `--approval-mode default --sandbox`
- auto mode maps to `--approval-mode auto_edit`
- yolo mode maps to `--approval-mode yolo`
- plan mode maps to `--approval-mode plan`

## Session persistence

Local help exposes session listing, resuming, and deletion, but does not show a no-persist flag or a reliable current-run session id in the help surface.

What this means for `ccc`:

- Python and Rust warn by default that Gemini may save a session
- `--save-session` keeps the current Gemini behavior and suppresses that warning
- `--cleanup-session` warns that automatic cleanup is unsupported for Gemini
- `ccc` does not delete guessed Gemini sessions

## Version discovery

`gemini --version` is supported, but local installs may route through an `npx --yes @google/gemini-cli` wrapper. Python and Rust avoid that slow path when package metadata is available:

- resolve `gemini` through symlinks
- read adjacent `@google/gemini-cli` `package.json` metadata for direct package installs
- when the launcher references `@google/gemini-cli`, scan the local npm `_npx` cache for `node_modules/@google/gemini-cli/package.json`
- report `npx @google/gemini-cli` for npx wrapper launchers when package metadata is missing, instead of spawning npm
- fall back to `gemini --version` only for non-wrapper layouts when metadata is missing

## Output modes

Gemini supports raw text, raw JSON, and formatted transcript modes in Python and Rust:

- raw text uses the default text output
- raw JSON uses `--output-format json`
- streaming JSON uses `--output-format stream-json`
- `formatted` and `stream-formatted` also use `--output-format stream-json`, parsing Gemini `message` events with `role: "assistant"` and result `stats`

## Quick checks

```sh
gemini --version
gemini --help
gemini --prompt "Respond with exactly pong"
gemini --prompt "Respond with exactly pong" --output-format json
gemini --prompt "Respond with exactly pong" --output-format stream-json
```

## Notes for `ccc`

- `ccc` uses `gemini --prompt`
- the canonical selectors are `gemini` and `g`
- Python and Rust support `CCC_REAL_GEMINI` for mock or local smoke overrides

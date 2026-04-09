# Stream Output Visual Systems

This file records the styling direction explored for human-readable streaming output.

## Default: Signal Forge

Signal Forge is the shipped default for Python and Rust TTY rendering.

Why it won:

- strong event identity without looking like log spam
- works with both chat deltas and tool activity
- clean non-TTY fallback
- emoji lane markers remain readable even when ANSI is stripped

TTY lane markers:

| Event | Marker | Intent |
|---|---|---|
| assistant | `💬` | bright primary chat lane |
| thinking | `🧠` | dimmed internal reasoning lane |
| tool start | `🛠️` | active work lane |
| tool result | `📎` | result/attachment lane |
| success/final | `✅` | completion lane |
| error | `❌` | failure lane |

Plain fallback:

- `[assistant]`
- `[thinking]`
- `[tool:start]`
- `[tool:result]`
- `[ok]`
- `[error]`

Color override rules:

- `FORCE_COLOR` forces the emoji/ANSI TTY lane markers on in human-formatted output
- `NO_COLOR` forces the plain fallback labels on
- if both are set, `FORCE_COLOR` wins

## Alternative: Ledger

Ledger is the restrained editorial variant:

- monochrome-first
- timestamp/logbook feel
- best for teams that want low visual noise

It was not chosen for v1 because tool and chat lanes feel too similar during heavy streams.

## Alternative: Blackbox Deck

Blackbox Deck is the operator-console variant:

- bolder color blocking
- denser line chrome
- stronger “control room” identity

It was not chosen for v1 because it is more opinionated and more likely to age badly in long sessions.

## Rendering Rules

- Thinking stays hidden unless `--show-thinking` is enabled.
- Human-formatted output falls back to plain labels unless `FORCE_COLOR` is set or `NO_COLOR` disables colors.
- Bash tool output shows the executed command digest up to 400 characters.
- File-edit tools are summarized; full file contents and diffs are intentionally hidden.
- Tool previews are capped at 8 lines and 400 visible characters.

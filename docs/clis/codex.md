# Codex CLI

## Status

- Verified against local binary on 2026-04-09: `codex`
- Local version checked: `codex-cli 0.118.0`
- Primary reference:
  - local `codex exec --help`

## Non-interactive shape

```sh
codex exec --ephemeral "your prompt"
```

Structured output shape:

```sh
codex exec --json --ephemeral "your prompt"
```

Explicit shared-daemon opt-out:

```sh
codex --no-daemon exec --ephemeral "your prompt"
ccc c --standalone "your prompt"
```

`--no-daemon` is a root option and must precede `exec`; the installed Codex rejects `codex exec --no-daemon`. `ccc --standalone` and `ccc --no-daemon` place it correctly. Config defaults and alias profiles support `standalone = true|false`, including through the alias wizard. CLI overrides aliases, then defaults; `--no-standalone` omits the option and lets upstream select its default rather than forcing a daemon connection. Codex's internal in-process app-server remains available.

Useful flags from local help:

- `--model`
- `--sandbox read-only|workspace-write|danger-full-access`
- `--approve-for-me` (current releases)
- `--dangerously-bypass-approvals-and-sandbox`
- `--cd`
- `--add-dir`
- `--json`
- `--ephemeral`
- `-c key=value` config overrides
- `--enable <feature>` / `--disable <feature>` toggle a feature flag (equivalent to `-c features.<name>=true|false`); e.g. `fast_mode`

## Permission controls

Codex exposes meaningful safety controls, but they are coarser than OpenCode or Claude.

Documented local CLI surface:

- sandbox level selection
- `--approve-for-me` routes approval requests through automatic review with a workspace sandbox
- `--dangerously-bypass-approvals-and-sandbox`

What this means for `ccc`:

- yolo mode maps cleanly to `--dangerously-bypass-approvals-and-sandbox`
- `ccc --permission-mode auto` sets `-c 'approval_policy="on-request"' --sandbox workspace-write`, preserving the former `--full-auto` behavior; current Codex rejects `--full-auto`
- sandbox choice could plausibly be exposed later as a cross-runner concept, but only Codex currently makes that especially explicit in CLI flags

## Reasoning effort

Codex takes its reasoning effort from the `model_reasoning_effort` config key, set via `-c model_reasoning_effort=<value>`. `ccc` maps its thinking ladder onto this key:

| `ccc` level | token | codex effort |
| --- | --- | --- |
| `+0` | `+none` | `none` |
| `+1` | `+low` | `low` |
| `+2` | `+medium` | `medium` |
| `+3` | `+high` | `high` |
| `+4` | `+xhigh` | `xhigh` |
| `+5` | `+max` | `max` |
| `+6` | `+ultra` | `ultra` |

- Codex models advertise their own supported effort tiers. `+ultra` / `+6` request the `ultra` reasoning effort; unsupported model/effort combinations are rejected upstream. Other runners clamp higher levels to their supported maximum.
- Unlike other runners, codex has its own default effort: when no level is given (via token, alias, or global default), `ccc` emits `-c model_reasoning_effort=medium`, matching codex's native default. Set an explicit level to override.
- The effort override applies to any codex model. Effort values a given model does not support (for example `max` on a pre-5.6 model) are rejected by codex/the API, not by `ccc`.
- Verified on 2026-10-22: a real `codex exec` request with `-c model_reasoning_effort="ultra"` and `-c service_tier="ultrafast"` completed successfully. Profiles store ultra effort as `thinking = 6`; `ccc add --thinking ultra` and the wizard accept the named level.

## Quick checks

Python and Rust read `@openai/codex/package.json` directly, following symlinks and literal shell-wrapper paths, including paths using `$HOME`. They do not evaluate the wrapper or select an unrelated global package. Unknown layouts fall back to `codex --version`.

```sh
codex --version
codex exec --help
```

To inspect the effective documented safety surface quickly:

```sh
codex exec --help | rg "sandbox|approve-for-me|dangerously"
```

## Model fallback

Presets can list `fallback_models`. When codex fails with a capacity or overload error (`Selected model is at capacity`, `server_overloaded`) before any assistant output, `ccc` retries once per listed model. Models that are not in the cross-runner map stay on codex. `glm-5.3`, `llmp-glm-5-3`, and `glm-5.3-flash` are retried as grok (`grok --no-auto-update -p --model <id>`), keeping the preset's thinking level, output mode, and prompt. JSON and formatted output from that retry is parsed with the grok schema. A 401 or other authentication error, including `OpenAI account pool has no usable account credential`, does not fall back. MiniMax, Claude, and Astra model ids in the list are skipped; a preset whose primary model is Astra still runs that model. `ccc` prints `ccc: ran model <id>` on stderr and records that line in the run transcript.

```toml
[aliases.cx-reviewer]
runner = "codex"
model = "gpt-6.1-sol"
fallback_models = ["gpt-6-sol", "glm-5.3"]
```

## Service tiers

Python and Rust support `--service-tier default|fast|priority|ultrafast`:

```sh
ccc c --service-tier default "your prompt"
ccc c --service-tier fast "your prompt"
ccc c --service-tier ultrafast "your prompt"
```

These emit `codex exec -c 'service_tier="<tier>"'`. Codex maps `fast` to the request tier `priority`; `priority` is also accepted. Availability depends on the active model and account. Selecting a tier requests that service level; the server determines the tier actually served.

```toml
[defaults]
service_tier = "default"

[aliases.quick]
runner = "c"
service_tier = "ultrafast"
```

CLI controls override alias settings, which override `[defaults].service_tier`. Within CLI controls, the last tier selector wins. Omitting the setting leaves Codex's configuration intact. `default` explicitly requests standard service, including when Codex itself is configured for Fast or Ultrafast. The `ccc add` wizard distinguishes **inherit** (omit the field) from **default**.

The Codex `features.fast_mode` and `features.ultrafast_mode` flags enable UI controls; they do not select the requested tier. `ccc --fast` and `ccc --no-fast` select `fast` and `default` through `service_tier`.

Reference: [official Codex configuration reference](https://developers.openai.com/codex/config-reference).

## Notes for `ccc`

- `ccc` uses `codex exec`
- Python and Rust add `--ephemeral` by default so `ccc` runs do not persist Codex session files
- `ccc --save-session c ...` omits `--ephemeral` and restores normal Codex session saving
- Codex has no literal `--fast` CLI flag; `ccc --fast c ...` maps to `-c 'service_tier="fast"'` and `ccc --no-fast c ...` maps to `-c 'service_tier="default"'`
- runners without a fast mode warn `runner "<name>" does not support fast mode; ignoring --fast/--no-fast` and drop the flag
- Python and Rust map `json`, `stream-json`, `formatted`, and `stream-formatted` to `codex exec --json`
- the Codex JSONL parser extracts `thread.started.thread_id`, completed assistant messages, command execution start/result events, `turn.completed.usage`, and structured failure events from `error` / `turn.failed`
- Codex sometimes wraps an upstream error object as a JSON string inside `message` or `error.message`; Python and Rust decode that nested payload and render a concise formatted error such as `invalid_request_error (400): ...`
- do not depend on undocumented aliases that may happen to work locally
- if we add finer controls, Codex is a good fit for `--sandbox` style options

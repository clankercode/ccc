# CLI Notes

These files record the current state of each supported coding CLI from the perspective of `ccc`.

They intentionally mix:

- verified local help output
- upstream official docs when available
- `ccc`-specific notes about what is safe to normalize

Current files:

- [opencode.md](opencode.md)
- [claude.md](claude.md)
- [codex.md](codex.md)
- [kimi.md](kimi.md)
- [cursor.md](cursor.md)
- [gemini.md](gemini.md)
- [crush.md](crush.md)
- [roocode.md](roocode.md)
- [allow-deny-tool-plan.md](allow-deny-tool-plan.md)
- [output-mode-compatibility.md](output-mode-compatibility.md)
- [stream-output-visual-systems.md](stream-output-visual-systems.md)
- [output-mode-porting.md](output-mode-porting.md)
- [json-event-references.md](json-event-references.md)
- [mock-smoke.md](mock-smoke.md)
- [model-capabilities.json](model-capabilities.json)
- [updating-model-capabilities.md](updating-model-capabilities.md)

## Canonical Usage Block

All implementations now share the same help surface under the usage line:

- `ccc [controls...] "<Prompt>"`
- the shared core controls block for runner, `+thinking`, `:provider:model`, and `@name`
- two dense examples that exercise the shared syntax

Implementation-specific extras can still follow after that shared block where a runtime supports them.

## Permission Matrix

This table describes the current `ccc` mapping and the likely future shape for finer-grained controls.

| CLI | Current `ccc --yolo` mapping | Fine-grained permission controls available upstream? | Best next exposed control |
|---|---|---|---|
| OpenCode | `OPENCODE_CONFIG_CONTENT='{"permission":"allow"}'` | Yes | `--permission-mode` and later tool allow/deny |
| Claude | `--dangerously-skip-permissions` | Yes | `--permission-mode`, `--allow-tool`, `--deny-tool` |
| Codex | `--dangerously-bypass-approvals-and-sandbox` | Partly | `--permission-mode` or `--sandbox` |
| Kimi | `--yolo` | Not much beyond yolo/plan | maybe `--plan` |
| Cursor Agent | `--yolo` | Partly | `--permission-mode` or `--sandbox` |
| Gemini CLI | `--approval-mode yolo` | Yes | `--permission-mode` |
| Crush | warn and ignore | Not reliable for non-interactive run mode | none until upstream CLI is clearer |
| RooCode | warn and ignore | Unverified | none until upstream CLI is verified |

## Thinking Matrix

`ccc` keeps the external thinking contract numeric. The top tier is vendor labeled: Anthropic says `max`, OpenAI-style labels say `xhigh`.

| `ccc` token | Anthropic / Claude | OpenAI-style | Notes |
|---|---|---|---|
| `+0` | `disabled` | `disabled` | off |
| `+1` | `low` | `low` | first non-off tier |
| `+2` | `medium` | `medium` | middle tier |
| `+3` | `high` | `high` | explicit high tier |
| `+4` | `max` | `xhigh` | same semantic top tier; label differs |

Kimi does not expose the same numeric ladder; `ccc` currently maps `+0` to `--no-thinking` and `+1..+4` to `--thinking`.

## Model Thinking Capability Source Of Truth

The shared source of truth is [model-capabilities.json](model-capabilities.json), not this markdown file.

Use it for:

- auth-scoped model inventory snapshots
- model-family thinking ladder notes
- runner-specific provider/model-family notes
- visible-thinking support notes
- provider-label differences such as `max` vs `xhigh`
- periodic refresh work when new models drop

Current structured coverage summary:

| Provider | Family | Runner | Thinking mode | Visible thinking | Notes |
|---|---|---|---|---|---|
| Anthropic | `claude-4` | `cc` | ladder | yes | maps cleanly to `+0..+4` |
| OpenAI-style | `gpt-5` | `c` | ladder | unknown | top label is `xhigh` |
| Moonshot | `kimi-k2` | `k` | binary | yes | `+1..+4` collapse to `--thinking` |
| OpenCode | unverified | `oc` | unknown | yes | visible-thinking support known, tier mapping not yet verified |

If you update thinking-capability notes, follow [updating-model-capabilities.md](updating-model-capabilities.md) and update the JSON first.

## Current Cross-Runner Permission Modes

Python and Rust now implement `--permission-mode <safe|auto|yolo|plan>` with partial runner-specific mappings. The matrix below distinguishes explicit upstream controls from honest default passthroughs and unverified cases that warn.

| Proposed `ccc` mode | OpenCode | Claude | Codex | Kimi | Cursor | Gemini | Crush | RooCode |
|---|---|---|---|---|---|---|---|---|
| `safe` | `OPENCODE_CONFIG_CONTENT='{"permission":"ask"}'` | `--permission-mode default` | leave default permissions unchanged | leave default permissions unchanged | `--sandbox enabled` | `--approval-mode default --sandbox` | leave default permissions unchanged | unverified; warn and leave defaults |
| `auto` | likely config-driven `ask`/`allow` mix | `--permission-mode auto` | `--full-auto` | no honest mapping yet | no honest mapping yet | `--approval-mode auto_edit` | no honest mapping yet | unverified |
| `yolo` | `OPENCODE_CONFIG_CONTENT='{"permission":"allow"}'` | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` | `--yolo` | `--yolo` | `--approval-mode yolo` | unsupported in `run`; warn | unverified; warn |
| `plan` | no verified equivalent yet | `--permission-mode plan` | no verified equivalent yet | `--plan` | `--mode plan` | `--approval-mode plan` | no verified equivalent yet | unverified |

## Session Persistence

Python and Rust now default to avoiding user-visible saved sessions where the upstream CLI exposes a verified non-persistence control:

| CLI | Default `ccc` behavior | `--save-session` | `--cleanup-session` |
|---|---|---|---|
| Claude | adds `--no-session-persistence` | omits that flag | not needed |
| Codex | adds `--ephemeral` | omits that flag | not needed |
| OpenCode | warns that the run may save a session | suppresses the warning | deletes the emitted `sessionID` with `opencode session delete <id>` when available |
| Kimi | warns that the run may save a session | suppresses the warning | removes the matching session file under `KIMI_SHARE_DIR` or `~/.kimi` when the resume hint exposes an ID |
| Cursor Agent | warns that the run may save a session | suppresses the warning | warns that automatic cleanup is unsupported |
| Gemini CLI | warns that the run may save a session | suppresses the warning | warns that automatic cleanup is unsupported |
| Crush | warns that the run may save a session | suppresses the warning | warns that automatic cleanup is unsupported |
| RooCode | warns that the run may save a session | suppresses the warning | warns that automatic cleanup is unsupported |

Cleanup is best-effort and only uses session IDs produced by the run itself. It does not delete by "latest session" heuristics.

## Tool Control Outlook

- OpenCode and Claude are the real candidates for `--allow-tool` / `--deny-tool`.
- Codex, Cursor Agent, and Gemini are better fits for sandbox/approval controls than per-tool allow/deny.
- Kimi is mostly binary yolo/non-yolo from the currently documented surface.
- Crush and RooCode should stay conservative until the non-interactive permission surfaces are verified.

If a CLI changes upstream, the fastest refresh path is:

```sh
<cli> --version
<cli> --help
```

Then update the corresponding file here before changing `ccc` runner assembly.

When adding a new CLI, its note should record the verified non-interactive argv shape, permission controls, session persistence behavior, output modes, structured-output schema, version command behavior, and any faster local metadata source that can keep the `ccc --help` runner checklist from spawning a slow CLI.

For the Python and Rust help checklist, runner version discovery now prefers trusted install metadata when the local layout is known, then falls back to `<cli> --version`. Current fast paths cover OpenCode, Codex, and Gemini `package.json`, Kimi `dist-info/METADATA`, Claude versioned local install paths, Cursor Agent's bundled `agent-cli@...` release marker, and Gemini's local npm `_npx` cache when the launcher uses `@google/gemini-cli`. Gemini npx wrappers report the wrapper identity instead of spawning npm when cached metadata is unavailable.

## Output Modes

Python and Rust now share these output modes:

| Mode | Sugar | Meaning |
|---|---|---|
| `text` | `.text` | buffered raw output |
| `stream-text` | `..text` | live raw output |
| `json` | `.json` | buffered raw JSON |
| `stream-json` | `..json` | live NDJSON |
| `formatted` | `.fmt` | buffered human transcript |
| `stream-formatted` | `..fmt` | live human transcript |

See [output-mode-compatibility.md](output-mode-compatibility.md) for the runner matrix and [stream-output-visual-systems.md](stream-output-visual-systems.md) for the current TTY rendering design.

Human-formatted output honors `FORCE_COLOR` and `NO_COLOR` before falling back to TTY detection; raw modes are unchanged.

Explicit unsupported output-mode selectors fail. Unsupported `output_mode` values inherited from config defaults or aliases warn and fall back to text when `ccc` has only mapped text support for the selected runner.

Implementation notes for future language ports live in [output-mode-porting.md](output-mode-porting.md).

Upstream structured-output references live in [json-event-references.md](json-event-references.md).

## OSC Sanitization

Python and Rust now support:

- `--sanitize-osc`
- `--no-sanitize-osc`

Config support matches the flag:

- `[defaults].sanitize_osc = true|false`
- `[aliases.<name>].sanitize_osc = true|false`

Default behavior:

- `formatted` and `stream-formatted` sanitize disruptive OSC/control output by default
- `text`, `stream-text`, `json`, and `stream-json` keep their existing raw behavior
- OpenCode raw JSON cleanup remains always on so `oc json` stays machine-clean

Sanitization rules:

- preserve OSC 8 hyperlinks
- strip title-setting OSC sequences
- strip stray bell characters and other disruptive OSC side effects from human-facing output

Manual smoke checks:

- `scripts/smoke-output-modes.sh python cc stream-formatted`
- `scripts/smoke-output-modes.sh rust cc stream-formatted`
- swap `cc` for `k` or `oc`, and swap `stream-formatted` for `formatted`, `json`, or `stream-json` to inspect the other paths

For mock-based local smoke recipes that avoid temporary `PATH` symlinks, see [mock-smoke.md](mock-smoke.md).

## Alias Wizard

Python and Rust support `ccc add [-g] <alias>` for writing `[aliases.<name>]` config entries through line prompts:

```bash
ccc add mm27
ccc add mm27 --runner cc --model claude-4 --prompt "Review changes" --prompt-mode default --yes
```

Without `-g`, the command writes the same config file that `ccc config` resolves, creating a new global config under `XDG_CONFIG_HOME/ccc/config.toml` or `~/.config/ccc/config.toml` when no config exists. With `-g`, it ignores project-local config and writes the effective global config, preferring XDG over home when both exist.

Blank/default wizard answers omit alias keys. Existing aliases first ask whether to modify, replace, or cancel; `--yes` modifies existing aliases unless `--replace` is provided. Wizard menu prompts use color on TTYs, can be forced with `FORCE_COLOR=1`, and are disabled with `NO_COLOR=1`. Successful writes print a checkmarked heading followed by the written alias block indented for readability.

# CLI Notes

These files record the current state of each supported coding CLI from the perspective of `ccc`.

They intentionally mix:

- verified local help output
- upstream official docs when available
- `ccc`-specific notes about what is safe to normalize

Current files:

- [opencode.md](/home/xertrov/src/call-coding-clis/docs/clis/opencode.md)
- [claude.md](/home/xertrov/src/call-coding-clis/docs/clis/claude.md)
- [codex.md](/home/xertrov/src/call-coding-clis/docs/clis/codex.md)
- [kimi.md](/home/xertrov/src/call-coding-clis/docs/clis/kimi.md)
- [crush.md](/home/xertrov/src/call-coding-clis/docs/clis/crush.md)
- [roocode.md](/home/xertrov/src/call-coding-clis/docs/clis/roocode.md)
- [allow-deny-tool-plan.md](/home/xertrov/src/call-coding-clis/docs/clis/allow-deny-tool-plan.md)
- [output-mode-compatibility.md](/home/xertrov/src/call-coding-clis/docs/clis/output-mode-compatibility.md)
- [stream-output-visual-systems.md](/home/xertrov/src/call-coding-clis/docs/clis/stream-output-visual-systems.md)
- [output-mode-porting.md](/home/xertrov/src/call-coding-clis/docs/clis/output-mode-porting.md)
- [json-event-references.md](/home/xertrov/src/call-coding-clis/docs/clis/json-event-references.md)
- [model-capabilities.json](/home/xertrov/src/call-coding-clis/docs/clis/model-capabilities.json)
- [updating-model-capabilities.md](/home/xertrov/src/call-coding-clis/docs/clis/updating-model-capabilities.md)

## Permission Matrix

This table describes the current `ccc` mapping and the likely future shape for finer-grained controls.

| CLI | Current `ccc --yolo` mapping | Fine-grained permission controls available upstream? | Best next exposed control |
|---|---|---|---|
| OpenCode | `OPENCODE_CONFIG_CONTENT='{"permission":"allow"}'` | Yes | `--permission-mode` and later tool allow/deny |
| Claude | `--dangerously-skip-permissions` | Yes | `--permission-mode`, `--allow-tool`, `--deny-tool` |
| Codex | `--dangerously-bypass-approvals-and-sandbox` | Partly | `--permission-mode` or `--sandbox` |
| Kimi | `--yolo` | Not much beyond yolo/plan | maybe `--plan` |
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

The shared source of truth is [model-capabilities.json](/home/xertrov/src/call-coding-clis/docs/clis/model-capabilities.json), not this markdown file.

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

If you update thinking-capability notes, follow [updating-model-capabilities.md](/home/xertrov/src/call-coding-clis/docs/clis/updating-model-capabilities.md) and update the JSON first.

## Current Cross-Runner Permission Modes

Python and Rust now implement `--permission-mode <safe|auto|yolo|plan>` with partial runner-specific mappings.

| Proposed `ccc` mode | OpenCode | Claude | Codex | Kimi | Crush | RooCode |
|---|---|---|---|---|---|---|
| `safe` | default / ask-oriented config | default or `--permission-mode default` | default | default | default | unverified |
| `auto` | likely config-driven `ask`/`allow` mix | `--permission-mode auto` | `--full-auto` | no honest mapping yet | no honest mapping yet | unverified |
| `yolo` | `OPENCODE_CONFIG_CONTENT='{"permission":"allow"}'` | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` | `--yolo` | unsupported in `run`; warn | unverified; warn |
| `plan` | no verified equivalent yet | `--permission-mode plan` | no verified equivalent yet | `--plan` | no verified equivalent yet | unverified |

## Tool Control Outlook

- OpenCode and Claude are the real candidates for `--allow-tool` / `--deny-tool`.
- Codex is a better fit for sandbox/approval controls than per-tool allow/deny.
- Kimi is mostly binary yolo/non-yolo from the currently documented surface.
- Crush and RooCode should stay conservative until the non-interactive permission surfaces are verified.

If a CLI changes upstream, the fastest refresh path is:

```sh
<cli> --version
<cli> --help
```

Then update the corresponding file here before changing `ccc` runner assembly.

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

See [output-mode-compatibility.md](/home/xertrov/src/call-coding-clis/docs/clis/output-mode-compatibility.md) for the runner matrix and [stream-output-visual-systems.md](/home/xertrov/src/call-coding-clis/docs/clis/stream-output-visual-systems.md) for the current TTY rendering design.

Implementation notes for future language ports live in [output-mode-porting.md](/home/xertrov/src/call-coding-clis/docs/clis/output-mode-porting.md).

Upstream structured-output references live in [json-event-references.md](/home/xertrov/src/call-coding-clis/docs/clis/json-event-references.md).

Manual smoke checks:

- `scripts/smoke-output-modes.sh python cc stream-formatted`
- `scripts/smoke-output-modes.sh rust cc stream-formatted`
- swap `cc` for `k` or `oc`, and swap `stream-formatted` for `formatted`, `json`, or `stream-json` to inspect the other paths

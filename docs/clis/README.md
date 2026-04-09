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

## Proposed Cross-Runner Permission Modes

These are not implemented yet, but they are the cleanest shape if we extend beyond `--yolo`.

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

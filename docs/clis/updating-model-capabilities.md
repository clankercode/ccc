# Updating Model Capabilities

`docs/clis/model-capabilities.json` is the source of truth for model-level thinking capability notes.

Do not treat the markdown table in [README.md](/home/xertrov/src/call-coding-clis/docs/clis/README.md) as authoritative. Update the JSON first, then refresh any summary tables or prose that cite it.

The JSON has two layers:

- `runner_discoveries`: raw or near-raw auth-scoped model inventories such as `opencode models`
- `models`: normalized capability rules for model families or runner/provider-route slices

## When To Update It

Refresh this file when:

- a new model family becomes a realistic `ccc` target
- a runner exposes a new model list or auth-scoped provider surface
- a supported CLI changes its thinking or reasoning flags
- a provider adds, renames, or removes a reasoning tier
- docs about thinking or permission behavior are being refreshed

## Minimum Update Procedure

1. Check the real CLI first.
2. Check any model-listing command the runner exposes.
3. Check the provider docs if the CLI help or model listing is ambiguous.
4. Record or refresh the discovery snapshot under `runner_discoveries`.
5. Update the normalized capability entries under `models`.
6. Update [README.md](/home/xertrov/src/call-coding-clis/docs/clis/README.md) if the human-facing summary changed.
7. Update [SHARED_CHANGES.md](/home/xertrov/src/call-coding-clis/SHARED_CHANGES.md) if shared semantics or maintainer expectations changed.

## Quick Verification Commands

Use the real CLI whenever possible:

```bash
claude --version
claude --help

codex --help
codex exec --help

kimi --help

opencode --help
opencode run --help
opencode models
```

If a command is flaky in the sandbox, retry it outside the sandbox before concluding that the runner no longer supports it. On this machine, `opencode models` failed inside the sandbox with a local DB error but succeeded outside the sandbox.

If the CLI help does not answer the question, run a small real invocation and inspect the failure mode:

```bash
ccc cc +4 "Respond with exactly pong"
ccc c +4 "Respond with exactly pong"
ccc k +1 "Respond with exactly pong"
```

The goal is not to get a successful model response every time. The goal is to verify that the argv shape and flags are still accepted by the real CLI.

If the runner exposes an auth-scoped model list, record what you learned from that command before editing the JSON. For OpenCode, `opencode models` is the first place to look because provider/model availability can depend on the current auth and configured providers.
When a runner exposes a full model list, capture the full list in `runner_discoveries` first, then choose representative entries from that list for `models` smoke checks and normalized capability rules.
Prefer the cheapest representative model that exercises the route. Only move to more expensive variants if the cheaper route is unavailable, ambiguous, or clearly behaves differently.

## Field Notes

- `thinking_mode = "ladder"` means the model family exposes a real multi-tier ladder that can honestly map to `+0..+4`.
- `thinking_mode = "binary"` means `ccc` may preserve the numeric surface, but upstream only supports on/off internally.
- `visible_thinking` records whether the runner can request visible reasoning output, not whether every model definitely emits it.
- Prefer family-level entries over one-off model IDs when the behavior is uniform within the family.
- It is valid to add runner-specific provider-family entries such as OpenCode `zai/*` when capability behavior depends on the runner or provider route, even if the underlying base model also appears elsewhere.
- If the same family behaves differently through different surfaces, split it into separate entries rather than forcing one global rule.
- Use `provider_route` when the runner exposes the same broad provider through multiple named routes or integrations and that routing matters for semantics.
- Set `auth_scoped` to `true` when availability depends on the local runner auth or configured provider set.
- `discovered_via` should list how the entry was established, such as `real_cli_model_listing`, `real_cli_help`, `real_cli_smoke`, or `upstream_docs`.
- For OpenCode specifically, `opencode models` is the inventory source; keep the auth-scoped list current and then smoke-test representative routes from that snapshot.

# Allow/Deny Tool Plan

## Goal

Add advanced permission controls to `ccc` where the underlying runner actually supports them, without pretending there is stronger cross-runner parity than exists.

## Scope

Phase 1 should be Python and Rust only.

Phase 1 should target:

- OpenCode
- Claude

Phase 1 should not target:

- Codex for `--allow-tool` / `--deny-tool`
- Kimi
- Crush
- RooCode

## Proposed CLI Surface

Cross-runner advanced flags:

- `--allow-tool <tool>`
- `--deny-tool <tool>`

Repeatable usage:

```sh
ccc cc --allow-tool Bash --allow-tool Edit "..."
ccc oc --deny-tool edit --deny-tool bash "..."
```

If both are present for the same tool, last-wins within the parsed control region.

## Parsing Rules

- Follow the same free-order pre-prompt control-token model already used for `--yolo`.
- Support repeated `--allow-tool` and repeated `--deny-tool`.
- Support `--` to force the rest of argv to be prompt text.
- Store raw requested tool rules in parsed args before runner-specific translation.

## Runner Mapping

### Claude

Map directly to:

- `--allowed-tools`
- `--disallowed-tools`

Notes:

- Claude tool names are runner-native, so v1 should use raw pass-through names rather than inventing a generic canonical tool taxonomy.
- If translation is added later, it should be additive, not required.

### OpenCode

Map to runtime config injection through `OPENCODE_CONFIG_CONTENT`.

Likely shape:

```json
{
  "permission": {
    "*": "ask",
    "bash": "allow",
    "edit": "deny"
  }
}
```

Notes:

- v1 should merge allow/deny requests into an inline config object and avoid writing user config files.
- preserve existing yolo handling precedence:
  - yolo should still mean global allow
  - tool allow/deny should either be rejected alongside yolo or explicitly documented as lower priority than yolo

## Unsupported Runners

For unsupported runners:

- emit a warning
- ignore the tool control flags

Phase 1 warning targets:

- Codex: no per-tool allow/deny mapping yet
- Kimi: no verified per-tool allow/deny mapping
- Crush: no reliable non-interactive permission mapping
- RooCode: unverified CLI surface

## Testing

Python and Rust:

- parser tests for repeated flags, ordering, `--`, and last-wins behavior
- resolver tests for Claude mapping
- resolver tests for OpenCode config injection
- warnings for unsupported runners

Shared tests:

- extend `tests/test_ccc_contract_impl.py` for Python and Rust only
- add runner-shape assertions for Claude
- add env/config assertions for OpenCode

## Open Design Questions

- Should we keep raw runner-native tool names only, or add an optional generic alias layer later?
- Should `--yolo` be mutually exclusive with `--allow-tool` / `--deny-tool`, or should yolo simply override them?
- Should a future `--permission-mode` be introduced before tool allow/deny, or alongside it?

## Recommendation

Do this after a small `--permission-mode` feature if we want a coherent safety story.

If we skip straight to tool controls, keep v1 narrow:

- OpenCode and Claude only
- raw runner-native tool names
- warnings everywhere else

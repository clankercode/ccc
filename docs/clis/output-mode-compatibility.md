# Output-Mode Compatibility

This matrix is the current Python and Rust contract for `ccc --output-mode` and the dot-sugar equivalents.

## Public Modes

| Mode | Sugar | Meaning |
|---|---|---|
| `text` | `.text` | buffered raw stdout/stderr passthrough |
| `stream-text` | `..text` | live raw stdout/stderr passthrough |
| `json` | `.json` | buffered raw JSON passthrough |
| `stream-json` | `..json` | live NDJSON passthrough |
| `formatted` | `.fmt` | buffered human transcript |
| `stream-formatted` | `..fmt` | live human transcript |

## Runner Matrix

| Runner | `text` | `stream-text` | `json` | `stream-json` | `formatted` | `stream-formatted` | Upstream transport used by `ccc` |
|---|---|---|---|---|---|---|---|
| Claude | yes | yes | yes | yes | yes | yes | `--output-format json` or `--verbose --output-format stream-json --include-partial-messages` |
| Kimi | yes | yes | no | yes | yes | yes | `--print --output-format stream-json` |
| OpenCode | yes | yes | yes | no | yes | no | `--format json` |
| Codex | yes | yes | no | no | no | no | native text only |
| Crush | yes | yes | no | no | no | no | native text only |
| RooCode | yes | yes | no | no | no | no | native text only |

## Notes

- Explicit unsupported modes are hard errors. `ccc` does not silently downgrade.
- Claude `stream-json` requires `--verbose` upstream. `ccc` adds that only for formatted streaming, not for raw passthrough.
- OpenCode uses `--format json`, not `-f json`. `-f` is the file-attach flag upstream.
- `formatted` and `stream-formatted` are normalized transcript modes, not raw passthrough.
- `stream-text` is intentionally separate from `stream-formatted`: it prints native runner output as it arrives.

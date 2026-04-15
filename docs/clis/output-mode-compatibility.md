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
| Cursor Agent | yes | yes | yes | yes | yes | yes | `--print --trust --output-format json` or `--print --trust --output-format stream-json` |
| Gemini CLI | yes | yes | yes | yes | yes | yes | `--prompt ... --output-format json` or `--prompt ... --output-format stream-json` |
| OpenCode | yes | yes | yes | no | yes | yes | `--format json` |
| Codex | yes | yes | yes | yes | yes | yes | `codex exec --json` |
| Crush | yes | yes | no | no | no | no | native text only |
| RooCode | yes | yes | no | no | no | no | native text only |

## Notes

- Explicit unsupported modes are hard errors. `ccc` does not silently downgrade a mode requested with `--output-mode` or dot sugar.
- Unsupported `output_mode` values from `[defaults]` or `[aliases.<name>]` warn and fall back to `text` so a broad config default does not break text-only runners.
- Claude `stream-json` requires `--verbose` upstream. `ccc` adds it for Claude `stream-json` and `stream-formatted`.
- OpenCode uses `--format json`, not `-f json`. `-f` is the file-attach flag upstream.
- OpenCode `--format json` is a live JSON-event stream, so `ccc` can drive both buffered `formatted` and live `stream-formatted` from the same upstream transport.
- Cursor Agent uses one-shot `--output-format json` for raw `json` and `--output-format stream-json` for NDJSON and formatted transcript modes.
- Gemini uses one-shot `--output-format json` for raw `json` and `--output-format stream-json` for NDJSON and formatted transcript modes.
- Codex uses `codex exec --json` for raw JSONL and formatted transcript modes; `ccc` maps assistant messages, command execution items, thread ids, and usage totals from that stream.
- `formatted` and `stream-formatted` are normalized transcript modes, not raw passthrough.
- `stream-text` is intentionally separate from `stream-formatted`: it prints native runner output as it arrives.
- `formatted` and `stream-formatted` sanitize disruptive OSC output by default while preserving OSC 8 hyperlinks.
- `--no-sanitize-osc` disables that human-facing cleanup; raw machine modes stay unchanged apart from the always-on OpenCode raw JSON cleanup.

## Run Artifacts

- Every `ccc` run creates a stable per-run artifact directory under the platform state root.
- The run directory name is client-prefixed, for example `opencode-<run-id>`.
- The directory always contains `output.txt`.
- The transcript file is `transcript.txt` for text and human transcript paths, including `text` requests that are upgraded into structured streaming, and `transcript.jsonl` for JSON-oriented paths.
- The CLI prints a parseable stderr footer in the form `>> ccc:output-log >> /abs/path/to/run-dir` unless `--no-output-log-path` is set.

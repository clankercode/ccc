# ccc Run Artifacts Design

**Goal:** make every `ccc` run leave behind a stable, script-friendly artifact directory that contains the final assistant message and the user-visible transcript, while optionally printing a machine-parsable footer line with that directory path.

**Rollout scope:** v1 lands in Python and Rust only. Those are the supported entry points for the first release of this contract. Other language ports stay unchanged for now and can be rolled out later from the same contract; scripts that need the footer should use a supported port until that follow-up lands.

## User-Facing Contract

When `ccc` runs a prompt through the normal execution path, it should:

- create a per-run artifact directory under the platform state directory
- write the final assistant message into `output.txt`
- write the user-visible primary transcript into either `transcript.txt` or `transcript.jsonl`
- print a single footer line to stderr at the end of the run in this shape:

```text
>> ccc:output-log >> /absolute/path/to/ccc/runs/<client>-<run-id>
```

That footer must be unique enough to parse reliably from scripts. The path portion should be an absolute path to the run directory, not to an individual file.

The footer is enabled by default and suppressible with a CLI flag. In v1, the CLI surface should support:

- `--output-log-path`
- `--no-output-log-path`

`--output-log-path` is a boolean enable flag, not a path-valued option. The default is to emit the footer. `--no-output-log-path` only suppresses the footer line; it does not disable artifact creation. If both flags appear, the last one wins.

This behavior applies to actual run invocations, not to `ccc config`, `ccc add`, or help output.

## Artifact Layout

Each run gets its own directory under a platform-appropriate state root:

- Unix with `XDG_STATE_HOME`: `$XDG_STATE_HOME/ccc/runs/<client>-<run-id>`
- Unix without `XDG_STATE_HOME`: `~/.local/state/ccc/runs/<client>-<run-id>`
- macOS: `~/Library/Application Support/ccc/runs/<client>-<run-id>`
- Windows: `%LOCALAPPDATA%\\ccc\\runs\\<client>-<run-id>`

The run id should be opaque and filesystem-safe. It should be generated from a collision-resistant timestamp plus process id plus a small monotonic or random suffix, and the directory should be created with exclusive creation plus retry. The client prefix should be the canonical runner name, such as `opencode`, `claude`, or `gemini`. Scripts should treat the footer path as the stable handle and should not parse the run id itself.

The directory should contain:

- `output.txt` - the final assistant message as plain UTF-8 text
- `transcript.txt` - the user-visible transcript for text and formatted modes
- `transcript.jsonl` - the user-visible transcript for JSON-oriented modes

The file names should be stable even when the final assistant message is empty, so scripts can rely on the folder layout instead of guessing which files exist.

Only one transcript file is written per run:

- `text`, `stream-text`, `formatted`, and `stream-formatted` use `transcript.txt`
- `json` and `stream-json` use `transcript.jsonl`
- if a `text` request is internally upgraded into structured streaming for visible OpenCode work, it still uses `transcript.txt` because the user-visible stream is the rendered human transcript

The transcript should mirror the exact primary output stream that `ccc` writes to stdout, not an internal parser representation. It must be accumulated from the same stdout-rendering path that the user sees, so streaming modes tee each emitted chunk into the transcript file as it is written. For example:

- `formatted` and `stream-formatted` transcript files should capture the exact rendered chunks that the CLI emits while processing structured events
- `text` and `stream-text` transcript files should capture the exact stdout-equivalent bytes after the existing raw-output sanitization
- `json` and `stream-json` transcript files should capture the exact JSON lines that the CLI emits after any existing raw-output sanitization

The artifact files do not need to persist stderr in v1. The footer line itself still goes to stderr so scripts can parse it from the live process stream.

Transcript files must not include cleanup warnings, artifact warnings, forwarded unknown JSON stderr lines, or the footer line.

## Runtime Flow

The existing runner APIs already provide the completed stdout and stderr payloads, so no new runner-level transport is required. The CLI should tee the live stdout-rendering path into the transcript artifact while the run is in flight, and then do the following after the run finishes:

1. resolve the normal output plan as it does today
2. create the artifact directory before writing any files
3. execute the runner and capture the completed stdout/stderr payloads
4. derive the final assistant message from the completed payload and the effective output mode
5. finalize `output.txt` and close the transcript file
6. print the footer line to stderr last, unless `--no-output-log-path` was supplied

The final assistant message should come from the structured parser result whenever the effective mode is `json`, `stream-json`, `formatted`, `stream-formatted`, or the CLI upgrades a `text` request into structured streaming for visible OpenCode work. In those cases, `output.txt` should use `ParsedJsonOutput.final_text`.

For `text` and `stream-text` when no structured upgrade happened, `output.txt` can fall back to the sanitized captured stdout stream because there is no richer structured final message to extract.

The implementation should not require changes to the core `Runner` abstraction. The CLI can reconstruct the final message from the captured completed run plus the existing JSON rendering helpers, but it must not rebuild the transcript from parser state if that would diverge from the exact stdout chunks that were emitted live.

## Failure Handling

Artifact emission must be best-effort and should not change the underlying runner exit code.

- If the artifact directory cannot be created, the CLI should print a warning to stderr and skip the footer line.
- If one artifact file fails to write, the CLI should still attempt the other and still print the footer if the run directory exists.
- If the footer can be printed, it should be the final stderr line from the run, after cleanup warnings.

That keeps the feature useful for scripts without turning a logging problem into a run failure.

## CLI Surface

This release keeps the public surface small:

- add `--output-log-path` and `--no-output-log-path` to the parser and help text
- default the flag to on
- do not add a TOML config key in v1
- do not add HTTP/HTTPS delivery yet; keep that in the backlog

The output-log footer is a runtime artifact signal, not a new run mode. It should work consistently across the existing text, raw JSON, and formatted transcript paths.

## Testing Strategy

The implementation should add focused tests in Python and Rust for:

- footer emission on the default path
- footer suppression with `--no-output-log-path`
- artifact directory creation
- `output.txt` contents for a structured run
- the correct transcript filename for text versus JSON-oriented output modes
- `stream-formatted` capture while the runner is still streaming
- the OpenCode visible-work upgrade path in text mode
- footer ordering after cleanup warnings

The shared contract suite should assert the new footer behavior for the Python and Rust `ccc` runs while leaving the help/config/add flows unchanged. Any tests that care about exact stderr output should either assert the footer explicitly or disable it with `--no-output-log-path`.

## Deferred Work

HTTP/HTTPS delivery remains deferred and is tracked in [TASKS.md](../../../TASKS.md). The artifact design here should stay simple enough that a later remote sink can be added without changing the footer format or the local file layout.

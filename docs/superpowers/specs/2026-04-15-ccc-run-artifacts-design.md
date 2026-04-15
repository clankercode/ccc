# ccc Run Artifacts Design

**Goal:** make every `ccc` run leave behind a stable, script-friendly artifact directory that contains the final assistant message and the user-visible transcript, while optionally printing a machine-parsable footer line with that directory path.

## User-Facing Contract

When `ccc` runs a prompt through the normal execution path, it should:

- create a per-run artifact directory under the platform state directory
- write the final assistant message into `output.txt`
- write the user-visible primary transcript into either `transcript.txt` or `transcript.jsonl`
- print a single footer line to stderr at the end of the run in this shape:

```text
>> ccc:output-log >> /absolute/path/to/ccc/runs/<run-id>
```

That footer must be unique enough to parse reliably from scripts. The path portion should be an absolute path to the run directory, not to an individual file.

The footer is enabled by default and suppressible with a CLI flag. In v1, the CLI surface should support:

- `--output-log-path`
- `--no-output-log-path`

The default is to emit the footer. `--no-output-log-path` only suppresses the footer line; it does not disable artifact creation.

This behavior applies to actual run invocations, not to `ccc config`, `ccc add`, or help output.

## Artifact Layout

Each run gets its own directory under a platform-appropriate state root:

- Unix with `XDG_STATE_HOME`: `$XDG_STATE_HOME/ccc/runs/<run-id>`
- Unix without `XDG_STATE_HOME`: `~/.local/state/ccc/runs/<run-id>`
- macOS: `~/Library/Application Support/ccc/runs/<run-id>`
- Windows: `%LOCALAPPDATA%\\ccc\\runs\\<run-id>`

The run id should be opaque and filesystem-safe. It only needs to be unique per invocation, so a timestamp plus process id is enough. Scripts should treat the footer path as the stable handle and should not parse the run id itself.

The directory should contain:

- `output.txt` - the final assistant message as plain UTF-8 text
- `transcript.txt` - the user-visible transcript for text and formatted modes
- `transcript.jsonl` - the user-visible transcript for JSON-oriented modes

The file names should be stable even when the final assistant message is empty, so scripts can rely on the folder layout instead of guessing which files exist.

Only one transcript file is written per run:

- `text`, `stream-text`, `formatted`, and `stream-formatted` use `transcript.txt`
- `json` and `stream-json` use `transcript.jsonl`

The transcript should mirror the user-visible output format, not an internal parser representation. For example, the formatted transcript should contain the rendered human transcript that `ccc` prints, and the JSON transcript should contain the JSON lines that `ccc` prints after any existing raw-output sanitization.

The artifact directory does not need to persist stderr in v1. The footer line itself still goes to stderr so scripts can parse it from the live process stream.

## Runtime Flow

The existing runner APIs already capture stdout and stderr, so no new runner-level transport is required. The CLI should do the following after a run finishes:

1. resolve the normal output plan as it does today
2. create the artifact directory before writing any files
3. execute the runner and capture the completed stdout/stderr payloads
4. derive the final assistant message from the completed payload and the resolved output mode
5. write `output.txt` and the transcript file
6. print the footer line to stderr last, unless `--no-output-log-path` was supplied

The final assistant message should come from the same structured parsing logic already used for the formatted modes. For raw text modes, the final output file can fall back to the captured stdout stream because there is no richer structured final message to extract.

The implementation should not require changes to the core `Runner` abstraction. The CLI can reconstruct the final message and transcript from the captured completed run plus the existing JSON rendering helpers.

## Failure Handling

Artifact emission must be best-effort and should not change the underlying runner exit code.

- If the artifact directory cannot be created, the CLI should print a warning to stderr and skip the footer line.
- If one artifact file fails to write, the CLI should still attempt the other.
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
- footer ordering after cleanup warnings

The shared contract suite should assert the new footer behavior for `ccc` runs while leaving the help/config/add flows unchanged. Any tests that care about exact stderr output should either assert the footer explicitly or disable it with `--no-output-log-path`.

## Deferred Work

HTTP/HTTPS delivery remains deferred and is tracked in [TASKS.md](../../../TASKS.md). The artifact design here should stay simple enough that a later remote sink can be added without changing the footer format or the local file layout.

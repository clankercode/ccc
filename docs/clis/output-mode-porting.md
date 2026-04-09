# Output-Mode Porting Notes

These notes describe the implementation shape that now exists in Python and Rust, so future language ports can match the same contract instead of rediscovering it.

## Parser Surface

Required public surface:

- `--output-mode <text|stream-text|json|stream-json|formatted|stream-formatted>`
- `-o` shorthand
- dot-sugar aliases before the prompt:
  - `.text` / `..text`
  - `.json` / `..json`
  - `.fmt` / `..fmt`
- last explicit selector wins
- `--` still escapes control parsing

## Config Surface

Support these config keys:

- `[defaults].output_mode = "formatted"`
- legacy `default_output_mode = "formatted"`
- `[aliases.<name>].output_mode = "stream-formatted"`

Config precedence:

1. explicit CLI selector
2. alias `output_mode`
3. config default
4. fallback `text`

## Runner Capability Resolution

Keep an `OutputPlan`-style resolved shape with:

- `runner_name`
- `mode`
- `stream`
- `formatted`
- `schema`
- `argv_flags`

Do not mix raw and formatted semantics:

- raw modes pass native runner output through
- formatted modes use structured transport and normalize events

## Structured Parsing

Current normalized event classes used by Python and Rust:

- assistant text
- text delta
- thinking delta
- tool start
- tool input delta
- tool result
- final result
- error

Claude-specific note:

- `stream-json` only produced usable partial deltas in local verification when `--verbose` was present
- keep that transport detail in the runner plan layer, not in renderer logic

OpenCode-specific note:

- upstream uses `--format json`
- `-f` is the file flag

## Formatted Renderer

Renderer requirements:

- track tool calls by id
- accumulate partial tool input for command previews
- dedupe repeated final text after streamed assistant text
- hide thinking by default
- emit plain labels when not on a TTY

Tool rendering rules:

- Bash/Shell: show command preview up to 400 chars
- file read/write/edit: summary only
- generic tool result preview: max 8 lines, max 400 chars

## Fixture Layout

Use:

`tests/fixtures/runner-transcripts/<runner>/<scenario>/`

Each scenario should contain:

- `prompt.txt`
- `stdout.ndjson` or `stdout.json`
- `stderr.txt`
- `meta.json`

Redact:

- session ids
- UUIDs
- tool ids
- absolute home/temp paths
- noisy bootstrap payloads that are not parser-relevant

## Porting Checklist

1. Implement parser and config support.
2. Add resolved output-plan logic.
3. Separate raw passthrough from structured formatted modes.
4. Add incremental stream handling.
5. Add formatted renderer with the same truncation rules.
6. Add fixture-driven parser/render tests.
7. Run the shared contract tests after the language-specific unit tests pass.

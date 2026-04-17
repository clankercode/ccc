# call_coding_clis Python Package

Python library and `ccc` CLI implementation for calling terminal-first coding agents through a small subprocess API. The Python implementation is one of the reference implementations for parser, config, structured output, and cross-language CLI behavior.

## Install For Development

From the repository root:

```bash
PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_parser_config tests.test_json_output tests.test_run_artifacts
```

For the targeted implementation check:

```bash
./test_impl.sh python
```

## Library API

```python
from call_coding_clis import CommandSpec, Runner

spec = CommandSpec(
    argv=["opencode", "run", "Explain this code"],
    cwd="/path/to/project",
)

result = Runner().run(spec)
print(result.stdout)
```

Streaming uses a callback that receives `stdout` or `stderr` plus the chunk text:

```python
from call_coding_clis import CommandSpec, Runner

spec = CommandSpec(argv=["opencode", "run", "Build a CLI"])

def on_chunk(channel: str, chunk: str) -> None:
    print(f"{channel}: {chunk}", end="")

result = Runner().stream(spec, on_chunk)
```

Public helpers exported by `call_coding_clis` include `CommandSpec`, `CompletedRun`, `Runner`, `build_prompt_spec`, `parse_args`, `resolve_command`, `load_config`, `render_example_config`, and `resolve_human_tty`.

## CLI Usage

```bash
ccc "fix the bug"
ccc cc "review my changes"
ccc c "write tests"
ccc k "explain this function"
ccc cu "inspect this branch"
ccc g "summarize this file"
ccc ..fmt "show tool work as it streams"
```

Control tokens are accepted in free order before the prompt:

```bash
ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
ccc --permission-mode auto c "Refactor the parser"
ccc -- "use --yolo literally in the prompt"
```

Supported runner selectors include `oc`/`opencode`, `cc`/`claude`, `c`/`cx`/`codex`, `k`/`kimi`, `cu`/`cursor`, `g`/`gemini`, `rc`/`roocode`, and `cr`/`crush`.

## Config

Python loads config in merge order:

1. `~/.config/ccc/config.toml`
2. `XDG_CONFIG_HOME/ccc/config.toml`
3. nearest project-local `.ccc.toml` searched upward from the current directory

When `CCC_CONFIG` points at an existing file, that file wins as the only loaded config. For `ccc config`, a missing `CCC_CONFIG` falls back to the normal chain.

Useful config commands:

```bash
ccc --print-config
ccc config
ccc config --edit
ccc config --edit --user
ccc config --edit --local
```

`ccc config --edit` opens the selected config in `$EDITOR`. `--user` targets the XDG/home user config. `--local` targets the nearest `.ccc.toml`, or creates one in the current directory if none exists.

Add aliases interactively or non-interactively:

```bash
ccc add reviewer
ccc add reviewer --runner cc --prompt "Review the current changes" --prompt-mode default --yes
```

The interactive wizard skips `prompt_mode` when prompt is unset. Final save confirmation accepts only `y`, `n`, `yes`, or `no`, case-insensitively.

## Output And Artifacts

Output modes are `text`, `stream-text`, `json`, `stream-json`, `formatted`, and `stream-formatted`, with dot shortcuts `.text`, `..text`, `.json`, `..json`, `.fmt`, and `..fmt`.

By default, `ccc` writes a run directory under the platform state root with `output.txt` plus one transcript file: `transcript.txt` for text and human-rendered modes, or `transcript.jsonl` for JSON-oriented modes. The stderr footer is parseable:

```text
>> ccc:output-log >> /abs/path/to/run-dir
```

Use `--no-output-log-path` to suppress that footer.

Pass `--timeout-secs <N>` to kill the wrapped runner after `N` seconds. `ccc` prints `warning: timed out after N seconds; killed runner` to stderr and exits with status `124`.

## Environment

| Variable | Purpose |
|----------|---------|
| `CCC_REAL_OPENCODE` | Override OpenCode binary path |
| `CCC_REAL_CLAUDE` | Override Claude binary path |
| `CCC_REAL_KIMI` | Override Kimi binary path |
| `CCC_REAL_CURSOR` | Override Cursor Agent binary path |
| `CCC_REAL_GEMINI` | Override Gemini binary path |
| `CCC_CONFIG` | Explicit config file path |
| `CCC_FWD_UNKNOWN_JSON` | Forward unhandled structured JSON lines to stderr in formatted modes; defaults on for now |
| `FORCE_COLOR` | Force colored human output |
| `NO_COLOR` | Disable colored human output |

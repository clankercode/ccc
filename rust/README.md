# ccc

`ccc` is both:

- a CLI for driving coding-agent tools through one consistent command surface
- a Rust crate that exposes the same parsing, planning, runner, transcript, and config helpers

It supports OpenCode, Claude Code, Codex, Kimi, Cursor Agent, Gemini CLI, RooCode, and Crush.

The published package is named `ccc`. The library crate name is `call_coding_clis`.

## Install

Install the CLI from crates.io:

```bash
cargo install ccc
```

Add the library to a Rust project:

```toml
[dependencies]
ccc = "0.1.2"
```

Then import the library crate as:

```rust
use call_coding_clis::{CommandSpec, Runner};
```

## What The CLI Covers

The `ccc` binary handles:

- runner selection across supported coding CLIs
- model, provider, thinking, and permission controls
- raw, streaming, JSON, and formatted output modes
- config-backed aliases and project-local `.ccc.toml`
- per-run artifact directories and transcript files
- runner-specific warnings around session persistence and compatibility

## CLI Quick Start

Use OpenCode by default:

```bash
ccc "fix the failing tests"
```

Pick an explicit runner:

```bash
ccc cc "review my changes"
ccc c "write a regression test"
ccc k "explain this function"
ccc cu "inspect this branch"
ccc g "summarize this file"
```

Controls can appear before the prompt in any order:

```bash
ccc cc +3 "review this patch"
ccc c :openai:gpt-5.4-mini "debug the parser"
ccc @reviewer "current changes"
ccc ..fmt cc "investigate the failing test"
ccc --yolo c "make the focused fix"
ccc -- "write about --yolo literally"
```

Help is available through any of these forms:

```bash
ccc help
ccc --help
ccc -h
```

## Library Quick Start

### Run a CLI command directly

```rust,no_run
use call_coding_clis::{CommandSpec, Runner};

let spec = CommandSpec::new(["opencode", "run", "Explain this module"]);
let result = Runner::new().run(spec);

println!("{}", result.stdout);
```

### Build a request and let `Client` plan it

```rust,no_run
use call_coding_clis::{Client, Request, RunnerKind};

let request = Request::new("review the latest changes")
    .with_runner(RunnerKind::Claude);

let plan = Client::new().plan(&request)?;

assert!(!plan.command_spec().argv.is_empty());
# Ok::<(), call_coding_clis::Error>(())
```

### Parse familiar `ccc`-style tokens into a typed request

```rust
use call_coding_clis::{parse_tokens_with_config, CccConfig, RunnerKind};

let config = CccConfig::default();
let parsed = parse_tokens_with_config(
    ["c", ":openai:gpt-5.4-mini", "debug this"],
    &config,
) ?;

assert_eq!(parsed.request.runner(), Some(RunnerKind::Codex));
assert_eq!(parsed.request.model(), Some("gpt-5.4-mini"));
# Ok::<(), call_coding_clis::Error>(())
```

### Stream output incrementally

```rust,no_run
use call_coding_clis::{CommandSpec, Runner};

let spec = CommandSpec::new(["opencode", "run", "Explain this module"]);
let runner = Runner::new();

let completed = runner.stream(spec, |channel, chunk| {
    if channel == "stdout" {
        print!("{chunk}");
    } else {
        eprint!("{chunk}");
    }
});

println!("exit code: {}", completed.exit_code);
```

## Runner Selectors

| Selector | Runner |
| --- | --- |
| `oc`, `opencode` | OpenCode |
| `cc`, `claude` | Claude Code |
| `c`, `cx`, `codex` | Codex |
| `k`, `kimi` | Kimi |
| `cu`, `cursor` | Cursor Agent |
| `g`, `gemini` | Gemini CLI |
| `rc`, `roocode` | RooCode |
| `cr`, `crush` | Crush |

## Output Modes

`ccc` can pass through raw output, stream output, or parse supported JSON streams into a stable human transcript.

| Mode | Sugar | Use |
| --- | --- | --- |
| `text` | `.text` | Raw stdout/stderr |
| `stream-text` | `..text` | Raw output while the runner is still working |
| `json` | `.json` | Raw structured output |
| `stream-json` | `..json` | Structured output while the runner is still working |
| `formatted` | `.fmt` | Parsed, human-readable transcript |
| `stream-formatted` | `..fmt` | Parsed transcript while the runner is still working |

Unhandled structured JSON is always preserved in run transcripts. In formatted modes, `--forward-unknown-json` or `CCC_FWD_UNKNOWN_JSON` controls whether unknown objects are also forwarded to stderr. The environment default is currently on.

## Config And Aliases

`ccc` reads config from the normal user config locations plus the nearest project-local `.ccc.toml` searched upward from the current directory.

Merge order:

1. `~/.config/ccc/config.toml`
2. `XDG_CONFIG_HOME/ccc/config.toml`
3. nearest `.ccc.toml`

When `CCC_CONFIG` points at an existing file, it is used as the only config file. If `CCC_CONFIG` is set but missing, `ccc config` falls back to the normal chain and reports the missing explicit path.

Useful config commands:

```bash
ccc --print-config
ccc config
EDITOR=vim ccc config --edit --user
EDITOR=vim ccc config --edit --local
ccc add reviewer --runner cc --prompt "Review the current changes" --yes
```

Example alias:

```toml
[aliases.reviewer]
runner = "cc"
provider = "anthropic"
model = "claude-sonnet-4-20250514"
thinking = 3
show_thinking = true
output_mode = "formatted"
prompt = "Review the current changes"
prompt_mode = "default"
```

Then run it with:

```bash
ccc @reviewer "focus on parser changes"
```

## Run Artifacts

By default, each CLI run writes an artifact directory under the platform state root, for example:

```text
~/.local/state/ccc/runs/opencode-<run-id>/
```

Each run directory contains `output.txt` plus exactly one transcript file:

- `transcript.txt` for text and human-rendered output
- `transcript.jsonl` for JSON-oriented output

The CLI prints a parseable footer on stderr:

```text
>> ccc:output-log >> /abs/path/to/run-dir
```

Use `--no-output-log-path` to suppress the footer without disabling artifact writes.

## Public Rust API

The crate is split into a few main entry points:

- `CommandSpec` and `Runner` for direct subprocess execution
- `Request`, `Client`, `Plan`, and `Run` for the typed invoke API
- `parse_tokens_with_config` and `sugar::parse_tokens` for `ccc`-style token parsing
- `Transcript`, `Event`, `ToolCall`, and `ToolResult` for parsed structured output
- config and help utilities such as `load_config`, `render_example_config`, and `print_help`

### Direct execution with `CommandSpec`

```rust
use call_coding_clis::CommandSpec;

let spec = CommandSpec::new(["claude", "-p", "review this"])
    .with_cwd("/home/user/project")
    .with_stdin("extra context")
    .with_env("ANTHROPIC_API_KEY", "sk-...");
```

### Execution with `Runner`

`Runner` executes a `CommandSpec` either as a blocking run or as a stream.

```rust
use call_coding_clis::{CommandSpec, Runner};

let spec = CommandSpec::new(["claude", "-p", "review this"]);

let runner = Runner::new();
let result = runner.run(spec);

println!("stdout: {}", result.stdout);
println!("stderr: {}", result.stderr);
println!("exit code: {}", result.exit_code);
```

Streaming delivers stdout and stderr chunks as they arrive:

```rust
let result = runner.stream(spec, |channel, chunk| {
    if channel == "stdout" {
        print!("{chunk}");
    } else {
        eprint!("{chunk}");
    }
});
```

### Typed planning with `Request` and `Client`

`Request` lets a Rust program express the same controls the CLI understands, while `Client` resolves that request into a runnable `Plan`.

```rust
use call_coding_clis::{Client, OutputMode, Request, RunnerKind};

let request = Request::new("summarize the failing test")
    .with_runner(RunnerKind::Codex)
    .with_model("gpt-5.4-mini")
    .with_output_mode(OutputMode::Formatted);

let client = Client::new();
let plan = client.plan(&request)?;

assert_eq!(plan.runner(), RunnerKind::Codex);
# Ok::<(), call_coding_clis::Error>(())
```

### `build_prompt_spec`

`build_prompt_spec` builds the default OpenCode command for a prompt:

```rust
use call_coding_clis::{build_prompt_spec, Runner};

let spec = build_prompt_spec("fix the off-by-one error")?;
let result = Runner::new().run(spec);
```

## Environment

| Variable | Purpose |
| --- | --- |
| `CCC_CONFIG` | Explicit config file path |
| `CCC_PROVIDER` | Provider override for the current run |
| `CCC_FWD_UNKNOWN_JSON` | Forward unknown structured JSON in formatted modes |
| `CCC_REAL_OPENCODE` | Override OpenCode binary path |
| `CCC_REAL_CLAUDE` | Override Claude binary path |
| `CCC_REAL_KIMI` | Override Kimi binary path |
| `CCC_REAL_CURSOR` | Override Cursor Agent binary path |
| `CCC_REAL_GEMINI` | Override Gemini binary path |
| `FORCE_COLOR` | Force formatted color output |
| `NO_COLOR` | Disable formatted color output |

## Release Artifacts

Published GitHub releases build native `ccc` binaries for Linux, macOS, and Windows. Cargo users can install from crates.io with `cargo install ccc`.

## License

Unlicense.

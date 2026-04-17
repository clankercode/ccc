# ccc — Call Coding CLIs

A Rust library and CLI for calling coding agents (OpenCode, Claude Code, Codex, Kimi, Cursor Agent, Gemini CLI, RooCode, and Crush) from Rust programs or a terminal. Run prompts against supported coding agents with a consistent subprocess interface, streaming support, structured output parsing, config-backed presets, and run artifacts.

## Quick Start

### Install the CLI

```bash
cargo install ccc
```

### Rust Library

```toml
[dependencies]
ccc = "0.1"
```

```rust
use call_coding_clis::{CommandSpec, Runner};

let runner = Runner::new();

// Build and run a command
let spec = CommandSpec::new(["opencode", "run", "Explain this code"])
    .with_cwd("/path/to/project");

let result = runner.run(spec);
println!("{}", result.stdout);
```

### CLI Usage

```bash
# Run a prompt with opencode (default)
ccc "fix the bug in main.rs"

# Use a different runner
ccc "review my changes"           # opencode (default)
ccc cc "review my changes"         # claude
ccc cx "write tests"               # codex
ccc k "explain this function"      # kimi
ccc cu "inspect this branch"        # cursor-agent
ccc g "summarize this file"         # gemini

# Thinking level (+0 to +4)
ccc +3 "design the API"           # highest thinking effort

# Model selection
ccc :claude-4 "hello"              # provider:model syntax
ccc : Sonnet 4 "hello"            # just model name

# Preset alias from config
ccc @reviewer "current changes"

# Force literal prompt (no flag parsing)
ccc -- "use --yolo in the prompt"

# Streaming output
ccc ..fmt "build a CLI"

# Config helpers
ccc --print-config
ccc config
EDITOR=vim ccc config --edit --local
```

## Library API

### CommandSpec

Describes a command to run: argv, stdin, working directory, and environment.

```rust
use call_coding_clis::CommandSpec;

// Minimal
let spec = CommandSpec::new(["opencode", "run", "hello"]);

// With options
let spec = CommandSpec::new(["claude", "-p", "review this"])
    .with_cwd("/home/user/project")
    .with_stdin("context here")
    .with_env("ANTHROPIC_API_KEY", "sk-...");
```

### CompletedRun

Result of a completed command run.

```rust
let result = runner.run(spec);
println!("stdout: {}", result.stdout);
println!("stderr: {}", result.stderr);
println!("exit code: {}", result.exit_code);
```

### Runner

Executes commands with blocking or streaming modes.

```rust
use call_coding_clis::Runner;

let runner = Runner::new();

// Blocking run
let result = runner.run(spec);

// Streaming with callback (stdout/stderr per line)
let result = runner.stream(spec, |channel, chunk| {
    if channel == "stdout" {
        print!("{}", chunk);
    } else {
        eprint!("{}", chunk);
    }
});
```

### build_prompt_spec

Convenience helper to build an opencode run command from a prompt string.

```rust
use call_coding_clis::build_prompt_spec;

let spec = build_prompt_spec("fix the off-by-one error")?;
let result = Runner::new().run(spec);
```

## CLI Reference

### Runner Selectors

| Shortcut | Runner     |
|----------|------------|
| `oc`     | opencode   |
| `cc`     | claude     |
| `c`, `cx`| codex      |
| `k`      | kimi       |
| `cu`     | cursor     |
| `g`      | gemini     |
| `rc`     | roocode    |
| `cr`     | crush      |

### Thinking Levels

```
+0 / +none   Disable thinking
+1 / +low    Low effort
+2 / +med    Medium effort (default for most)
+3 / +high   High effort
+4 / +max    Maximum effort
```

### Model Selection

```bash
ccc :provider:model "prompt"     # Full provider:model
ccc :model "prompt"              # Model only (uses default provider)
```

### Output Modes

| Mode              | Description                                      |
|-------------------|--------------------------------------------------|
| `text`            | Raw stdout/stderr                                |
| `stream-text`     | Stream raw output line-by-line                   |
| `json`            | Raw JSON (for runners that output JSON)          |
| `stream-json`     | Stream JSON line-by-line                         |
| `formatted`       | Parse and render structured output for humans    |
| `stream-formatted`| Stream parsed structured output                  |

Shortcuts: `.text`, `..text`, `.json`, `..json`, `.fmt`, `..fmt`

### Permission Modes

```bash
--permission-mode safe   # Ask before dangerous ops (default)
--permission-mode auto  # Auto-approve safe ops
--permission-mode yolo  # Skip all permission checks
--permission-mode plan  # Plan-only mode
-y / --yolo             # Shortcut for --permission-mode yolo
```

### Other Flags

```
--show-thinking         Show thinking in formatted output
--no-show-thinking      Hide thinking in formatted output
--sanitize-osc          Strip OSC escape sequences (titles, bells)
--no-sanitize-osc       Keep OSC escape sequences
--forward-unknown-json  Forward unparseable JSON lines to stderr
--print-config          Print example config file
--save-session          Allow normal runner session persistence
--cleanup-session       Try post-run session cleanup where supported
--output-log-path       Print the run-artifact footer on stderr
--no-output-log-path    Suppress the run-artifact footer
--                       Treat all following args as literal prompt
```

## Configuration

Config file merge order:
1. `~/.config/ccc/config.toml`
2. `XDG_CONFIG_HOME/ccc/config.toml`
3. nearest project-local `.ccc.toml` searched upward from the current directory

When `CCC_CONFIG` points to an existing file, it wins as the only loaded config. For `ccc config`, a missing `CCC_CONFIG` falls back to the normal chain.

Generate an example config:

```bash
ccc --print-config
```

Print active config files and raw contents:

```bash
ccc config
```

Open a config in `$EDITOR`:

```bash
ccc config --edit          # selected/resolved config
ccc config --edit --user   # XDG/home user config
ccc config --edit --local  # nearest .ccc.toml, or create one in CWD
```

Add or edit an alias with the line-prompt wizard:

```bash
ccc add mm27
ccc add mm27 --runner cc --model claude-4 --prompt "Review changes" --prompt-mode default --yes
```

Without `-g`, `ccc add` writes the same config path shown by `ccc config`, creating a new global config when none exists. With `-g`, it ignores project-local config and writes the effective global config.

In the interactive wizard, blank/default answers omit alias keys. `prompt_mode` is skipped when prompt is unset, and final save confirmation accepts only `y`, `n`, `yes`, or `no`.

Example `.ccc.toml`:

```toml
[defaults]
runner = "oc"
provider = "anthropic"
model = "claude-4"
thinking = 1
show_thinking = true
sanitize_osc = true
output_mode = "formatted"

[abbreviations]
mycc = "cc"

[aliases.reviewer]
runner = "cc"
provider = "anthropic"
model = "claude-4"
thinking = 3
show_thinking = true
output_mode = "formatted"
agent = "reviewer"
prompt = "Review the current changes"
prompt_mode = "default"
```

### Aliases

Aliases bundle runner, model, thinking level, and prompt into a single name:

```bash
ccc @reviewer "current changes"
```

The `@reviewer` alias might resolve to Claude with specific settings and a base prompt like "Review the current changes". Your explicit prompt is appended or prepended based on `prompt_mode`.

### Prompt Modes

- `default` — Use user prompt if provided, else alias prompt
- `prepend` — Add user prompt before alias prompt
- `append` — Add user prompt after alias prompt

## Run Artifacts

By default, `ccc` writes each run under the platform state root in a client-prefixed directory such as `opencode-<run-id>`. Each run directory contains `output.txt` and exactly one transcript file: `transcript.txt` for text and human-rendered modes, or `transcript.jsonl` for JSON-oriented modes. The CLI prints a parseable footer on stderr:

```text
>> ccc:output-log >> /abs/path/to/run-dir
```

Use `--no-output-log-path` to suppress the footer.

## Environment Variables

| Variable              | Purpose                                      |
|-----------------------|----------------------------------------------|
| `CCC_REAL_OPENCODE`   | Override opencode binary path (for testing) |
| `CCC_REAL_CLAUDE`     | Override claude binary path (for testing)    |
| `CCC_REAL_KIMI`       | Override kimi binary path (for testing)      |
| `CCC_REAL_CURSOR`     | Override cursor-agent binary path (for testing) |
| `CCC_REAL_GEMINI`     | Override gemini binary path (for testing)    |
| `CCC_PROVIDER`        | Set provider for current run                  |
| `CCC_CONFIG`          | Explicit config file path                     |
| `CCC_FWD_UNKNOWN_JSON` | Forward unhandled structured JSON lines to stderr in formatted modes; defaults on for now |
| `FORCE_COLOR`         | Force colored output                          |
| `NO_COLOR`            | Disable colored output                       |

## Supported Runners

| Runner    | Binary   | Thinking | Models | JSON Output | Formatted |
|-----------|----------|----------|--------|------------|-----------|
| opencode  | opencode | ✓        | ✓      | ✓          | ✓         |
| claude    | claude   | ✓        | ✓      | ✓          | ✓         |
| codex     | codex    | —        | ✓      | ✓          | ✓         |
| kimi      | kimi     | ✓        | ✓      | ✓          | ✓         |
| cursor    | cursor-agent | —    | ✓      | ✓          | ✓         |
| gemini    | gemini   | —        | ✓      | ✓          | ✓         |
| roocode   | roocode  | —        | —      | —          | —         |
| crush     | crush    | —        | —      | —          | —         |

## License

Unlicense

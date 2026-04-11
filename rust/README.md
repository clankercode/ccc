# ccc — Call Coding CLIs

A Rust library and CLI for calling coding agents (opencode, claude, codex, kimi, roocode, crush) from your Rust programs or terminal. Run prompts against any supported coding agent with a consistent interface, streaming support, and structured output parsing.

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
use ccc::{CommandSpec, Runner};

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
```

## Library API

### CommandSpec

Describes a command to run: argv, stdin, working directory, and environment.

```rust
use ccc::CommandSpec;

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
use ccc::Runner;

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
use ccc::build_prompt_spec;

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
--                       Treat all following args as literal prompt
```

## Configuration

Config file lookup order:
1. `.ccc.toml` in project directory (or nearest ancestor)
2. `XDG_CONFIG_HOME/ccc/config.toml`
3. `~/.config/ccc/config.toml`
4. `$CCC_CONFIG` (explicit path)

Generate an example config:

```bash
ccc --print-config
```

Add or edit an alias with the line-prompt wizard:

```bash
ccc add mm27
ccc add mm27 --runner cc --model claude-4 --prompt "Review changes" --prompt-mode default --yes
```

Without `-g`, `ccc add` writes the same config path shown by `ccc config`, creating a new global config when none exists. With `-g`, it ignores project-local config and writes the effective global config.

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

The `@reviewer` alias might resolve to claude with specific settings and a base prompt like "Review the current changes". Your explicit prompt is appended or prepended based on `prompt_mode`.

### Prompt Modes

- `default` — Use user prompt if provided, else alias prompt
- `prepend` — Add user prompt before alias prompt
- `append` — Add user prompt after alias prompt

## Environment Variables

| Variable              | Purpose                                      |
|-----------------------|----------------------------------------------|
| `CCC_REAL_OPENCODE`   | Override opencode binary path (for testing) |
| `CCC_REAL_CLAUDE`     | Override claude binary path (for testing)    |
| `CCC_REAL_KIMI`       | Override kimi binary path (for testing)      |
| `CCC_PROVIDER`        | Set provider for current run                  |
| `CCC_CONFIG`          | Explicit config file path                     |
| `FORCE_COLOR`         | Force colored output                          |
| `NO_COLOR`            | Disable colored output                       |

## Supported Runners

| Runner    | Binary   | Thinking | Models | JSON Output | Formatted |
|-----------|----------|----------|--------|------------|-----------|
| opencode  | opencode | ✓        | ✓      | ✓          | ✓         |
| claude    | claude   | ✓        | ✓      | ✓          | ✓         |
| codex     | codex    | —        | ✓      | —          | —         |
| kimi      | kimi     | ✓        | ✓      | ✓          | ✓         |
| roocode   | roocode  | —        | —      | —          | —         |
| crush     | crush    | —        | —      | —          | —         |

## License

Unlicense

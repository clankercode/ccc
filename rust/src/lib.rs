//! `ccc` is the Rust library behind the `ccc` CLI.
//!
//! It provides:
//!
//! - direct subprocess execution via [`CommandSpec`] and [`Runner`]
//! - a typed invoke layer via [`Request`], [`Client`], [`Plan`], and [`Run`]
//! - `ccc`-style token parsing via [`parse_tokens_with_config`] and [`sugar`]
//! - transcript parsing and rendering helpers for supported coding-agent CLIs
//! - config, alias, and help utilities shared with the published binary
//!
//! The package published on crates.io is named `ccc`, while the library crate name
//! is `call_coding_clis`.
//!
//! # Supported runners
//!
//! The current built-in runner registry covers:
//!
//! - OpenCode
//! - Claude Code
//! - Codex
//! - Kimi
//! - Cursor Agent
//! - Gemini CLI
//! - RooCode
//! - Crush
//!
//! # Choose an entry point
//!
//! Use [`CommandSpec`] and [`Runner`] when you already know the exact argv you want
//! to execute.
//!
//! Use [`Request`] and [`Client`] when you want a typed Rust API that mirrors the
//! `ccc` CLI's controls for runner selection, model/provider selection, output
//! modes, and session-related flags.
//!
//! Use [`parse_tokens_with_config`] when you want to accept familiar `ccc`-style
//! tokens and turn them into a typed [`Request`].
//!
//! # Examples
//!
//! Run a command directly:
//!
//! ```no_run
//! use call_coding_clis::{CommandSpec, Runner};
//!
//! let spec = CommandSpec::new(["opencode", "run", "Explain this module"]);
//! let result = Runner::new().run(spec);
//!
//! println!("stdout: {}", result.stdout);
//! ```
//!
//! Build and plan a typed request:
//!
//! ```no_run
//! use call_coding_clis::{Client, OutputMode, Request, RunnerKind};
//!
//! let request = Request::new("review the current patch")
//!     .with_runner(RunnerKind::Claude)
//!     .with_output_mode(OutputMode::Formatted);
//!
//! let plan = Client::new().plan(&request)?;
//!
//! assert_eq!(plan.runner(), RunnerKind::Claude);
//! assert!(!plan.command_spec().argv.is_empty());
//! # Ok::<(), call_coding_clis::Error>(())
//! ```
//!
//! Parse `ccc`-style tokens into a request:
//!
//! ```no_run
//! use call_coding_clis::{parse_tokens_with_config, CccConfig, RunnerKind};
//!
//! let parsed = parse_tokens_with_config(
//!     ["c", ":openai:gpt-5.4-mini", "debug this failure"],
//!     &CccConfig::default(),
//! )?;
//!
//! assert_eq!(parsed.request.runner(), Some(RunnerKind::Codex));
//! assert_eq!(parsed.request.model(), Some("gpt-5.4-mini"));
//! # Ok::<(), call_coding_clis::Error>(())
//! ```
//!
//! Stream stdout and stderr incrementally:
//!
//! ```no_run
//! use call_coding_clis::{CommandSpec, Runner};
//!
//! let spec = CommandSpec::new(["opencode", "run", "Describe the next step"]);
//! let runner = Runner::new();
//!
//! let completed = runner.stream(spec, |channel, chunk| {
//!     if channel == "stdout" {
//!         print!("{chunk}");
//!     } else {
//!         eprint!("{chunk}");
//!     }
//! });
//!
//! println!("exit code: {}", completed.exit_code);
//! ```
//!
//! # Output and transcript helpers
//!
//! For structured runner output, the crate also exports:
//!
//! - [`Transcript`], [`Event`], [`ToolCall`], [`ToolResult`], and [`Usage`]
//! - [`parse_transcript`] and [`parse_transcript_for_runner`]
//! - [`render_transcript`]
//! - formatted JSON helpers such as [`parse_json_output`] and
//!   [`StructuredStreamProcessor`]
//!
//! # Config and CLI helpers
//!
//! Shared config and CLI-facing utilities remain public for applications that want
//! to integrate with the same config files or help/config rendering used by the
//! `ccc` binary. The main entry points are:
//!
//! - [`load_config`]
//! - [`render_example_config`]
//! - [`find_config_command_path`] and [`find_config_command_paths`]
//! - [`write_alias_block`] and [`render_alias_block`]
//! - [`print_help`], [`print_usage`], and [`print_version`]
//!
mod artifacts;
mod config;
mod exec;
mod help;
mod invoke;
mod json_output;
mod output;
mod parser;
pub mod sugar;

pub use artifacts::{
    output_write_warning, resolve_state_root, transcript_io_warning, RunArtifacts, TranscriptKind,
};
pub use config::{
    find_alias_write_path, find_config_command_path, find_config_command_paths,
    find_config_edit_path, find_local_config_write_path, find_project_config_path,
    find_user_config_write_path, load_config, normalize_alias_name, render_alias_block,
    render_example_config, upsert_alias_block, write_alias_block,
};
pub use exec::{build_prompt_spec, CommandSpec, CompletedRun, Runner};
pub use help::{print_help, print_usage, print_version};
pub use invoke::{Client, Error, OutputMode, Plan, Request, Run, RunnerKind};
pub use json_output::{
    parse_claude_code_json, parse_codex_json, parse_cursor_agent_json, parse_gemini_json,
    parse_json_output, parse_kimi_json, parse_opencode_json, render_parsed, resolve_human_tty,
    FormattedRenderer, JsonEvent, ParsedJsonOutput, StructuredStreamProcessor, TextContent,
    ThinkingContent, ToolCall as JsonToolCall, ToolResult as JsonToolResult,
};
pub use output::{
    parse_transcript, parse_transcript_for_runner, render_transcript, schema_name_for_runner,
    Event, ToolCall, ToolResult, Transcript, Usage,
};
pub use parser::{
    parse_args, resolve_command, resolve_output_mode, resolve_output_plan, resolve_sanitize_osc,
    resolve_show_thinking, AliasDef, CccConfig, OutputPlan, ParsedArgs, RunnerInfo,
    RUNNER_REGISTRY,
};
pub use sugar::{parse_tokens_with_config, ParsedRequest};

mod artifacts;
mod config;
mod exec;
mod help;
mod invoke;
mod json_output;
mod parser;

pub use artifacts::{
    output_write_warning, resolve_state_root, transcript_io_warning, RunArtifacts, TranscriptKind,
};
pub use config::{
    find_alias_write_path, find_config_command_path, find_config_command_paths,
    find_config_edit_path, find_local_config_write_path, find_project_config_path,
    find_user_config_write_path, load_config, normalize_alias_name, render_alias_block,
    render_example_config, upsert_alias_block, write_alias_block,
};
pub use exec::{
    build_prompt_spec, CompletedRun, CommandSpec, Runner,
};
pub use help::{print_help, print_usage, print_version};
pub use invoke::{Client, OutputMode, Plan, Request, RunnerKind};
pub use json_output::{
    parse_claude_code_json, parse_codex_json, parse_cursor_agent_json, parse_gemini_json,
    parse_json_output, parse_kimi_json, parse_opencode_json, render_parsed, resolve_human_tty,
    FormattedRenderer, JsonEvent, ParsedJsonOutput, StructuredStreamProcessor, TextContent,
    ThinkingContent, ToolCall, ToolResult,
};
pub use parser::{
    parse_args, resolve_command, resolve_output_mode, resolve_output_plan, resolve_sanitize_osc,
    resolve_show_thinking, AliasDef, CccConfig, OutputPlan, ParsedArgs, RunnerInfo,
    RUNNER_REGISTRY,
};

use std::collections::BTreeMap;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

mod artifacts;
mod config;
mod help;
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
pub use help::{print_help, print_usage, print_version};
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandSpec {
    pub argv: Vec<String>,
    pub stdin_text: Option<String>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<String, String>,
}

impl CommandSpec {
    pub fn new<I, S>(argv: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        Self {
            argv: argv.into_iter().map(Into::into).collect(),
            stdin_text: None,
            cwd: None,
            env: BTreeMap::new(),
        }
    }

    pub fn with_stdin(mut self, stdin_text: impl Into<String>) -> Self {
        self.stdin_text = Some(stdin_text.into());
        self
    }

    pub fn with_cwd(mut self, cwd: impl Into<PathBuf>) -> Self {
        self.cwd = Some(cwd.into());
        self
    }

    pub fn with_env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.env.insert(key.into(), value.into());
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompletedRun {
    pub argv: Vec<String>,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

type StreamCallback = Arc<Mutex<dyn FnMut(&str, &str) + Send>>;
type RunExecutor = dyn Fn(CommandSpec) -> CompletedRun + Send + Sync;
type StreamExecutor = dyn Fn(CommandSpec, StreamCallback) -> CompletedRun + Send + Sync;

pub struct Runner {
    executor: Box<RunExecutor>,
    stream_executor: Box<StreamExecutor>,
}

impl Runner {
    pub fn new() -> Self {
        Self {
            executor: Box::new(default_run_executor),
            stream_executor: Box::new(default_stream_executor),
        }
    }

    pub fn with_executor(executor: Box<RunExecutor>) -> Self {
        Self {
            executor,
            stream_executor: Box::new(default_stream_executor),
        }
    }

    pub fn with_stream_executor(stream_executor: Box<StreamExecutor>) -> Self {
        Self {
            executor: Box::new(default_run_executor),
            stream_executor,
        }
    }

    pub fn run(&self, spec: CommandSpec) -> CompletedRun {
        (self.executor)(spec)
    }

    pub fn stream<F>(&self, spec: CommandSpec, on_event: F) -> CompletedRun
    where
        F: FnMut(&str, &str) + Send + 'static,
    {
        (self.stream_executor)(spec, Arc::new(Mutex::new(on_event)))
    }
}

impl Default for Runner {
    fn default() -> Self {
        Self::new()
    }
}

pub fn build_prompt_spec(prompt: &str) -> Result<CommandSpec, &'static str> {
    let normalized_prompt = prompt.trim();
    if normalized_prompt.is_empty() {
        return Err("prompt must not be empty");
    }
    Ok(CommandSpec::new(["opencode", "run", normalized_prompt]))
}

fn default_run_executor(spec: CommandSpec) -> CompletedRun {
    let mut command = build_command(&spec);
    let output = command
        .output()
        .unwrap_or_else(|error| failed_output(&spec, error));
    CompletedRun {
        argv: spec.argv,
        exit_code: output.status.code().unwrap_or(1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

fn default_stream_executor(spec: CommandSpec, callback: StreamCallback) -> CompletedRun {
    let argv = spec.argv.clone();
    let mut command = build_command(&spec);
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let error_msg = format!(
                "failed to start {}: {}",
                spec.argv.first().map(|s| s.as_str()).unwrap_or("(unknown)"),
                error
            );
            if let Ok(mut cb) = callback.lock() {
                cb("stderr", &error_msg);
            }
            return CompletedRun {
                argv,
                exit_code: 1,
                stdout: String::new(),
                stderr: error_msg,
            };
        }
    };

    if let Some(stdin_text) = &spec.stdin_text {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(stdin_text.as_bytes());
        }
    }

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();

    let cb_out = Arc::clone(&callback);
    let stdout_thread = thread::spawn(move || {
        let mut buf = String::new();
        if let Some(pipe) = stdout_pipe {
            use std::io::BufRead;
            let reader = std::io::BufReader::new(pipe);
            for line in reader.lines() {
                match line {
                    Ok(text) => {
                        buf.push_str(&text);
                        buf.push('\n');
                        let chunk = format!("{text}\n");
                        if let Ok(mut cb) = cb_out.lock() {
                            cb("stdout", &chunk);
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        buf
    });

    let cb_err = Arc::clone(&callback);
    let stderr_thread = thread::spawn(move || {
        let mut buf = String::new();
        if let Some(pipe) = stderr_pipe {
            use std::io::BufRead;
            let reader = std::io::BufReader::new(pipe);
            for line in reader.lines() {
                match line {
                    Ok(text) => {
                        buf.push_str(&text);
                        buf.push('\n');
                        let chunk = format!("{text}\n");
                        if let Ok(mut cb) = cb_err.lock() {
                            cb("stderr", &chunk);
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        buf
    });

    let stdout_buf = stdout_thread.join().unwrap_or_default();
    let stderr_buf = stderr_thread.join().unwrap_or_default();

    let status = child.wait().unwrap_or_else(|error| {
        std::process::ExitStatus::from_raw(
            failed_output(&spec, error).status.code().unwrap_or(1) as i32
        )
    });

    CompletedRun {
        argv,
        exit_code: status.code().unwrap_or(1),
        stdout: stdout_buf,
        stderr: stderr_buf,
    }
}

fn build_command(spec: &CommandSpec) -> Command {
    let mut argv = spec.argv.iter();
    let program = argv.next().cloned().unwrap_or_default();
    let mut command = Command::new(program);
    command.args(argv);
    if let Some(cwd) = &spec.cwd {
        command.current_dir(cwd);
    }
    command.envs(&spec.env);
    command.stdin(if spec.stdin_text.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    command
}

fn failed_output(spec: &CommandSpec, error: io::Error) -> std::process::Output {
    let stderr = format!(
        "failed to start {}: {}",
        spec.argv.first().map(|s| s.as_str()).unwrap_or("(unknown)"),
        error
    )
    .into_bytes();
    std::process::Output {
        status: std::process::ExitStatus::from_raw(1 << 8),
        stdout: Vec::new(),
        stderr,
    }
}

#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;

#[cfg(windows)]
use std::os::windows::process::ExitStatusExt;

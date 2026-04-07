use std::collections::BTreeMap;
use std::io;
use std::path::PathBuf;
use std::process::{Command, Stdio};

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

type StreamCallback<'a> = dyn FnMut(&str, &str) + 'a;
type RunExecutor = dyn Fn(CommandSpec) -> CompletedRun + Send + Sync;
type StreamExecutor =
    dyn for<'a> Fn(CommandSpec, Box<StreamCallback<'a>>) -> CompletedRun + Send + Sync;

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
        F: FnMut(&str, &str),
    {
        (self.stream_executor)(spec, Box::new(on_event))
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

fn default_stream_executor<'a>(
    spec: CommandSpec,
    mut callback: Box<StreamCallback<'a>>,
) -> CompletedRun {
    let result = default_run_executor(spec);
    if !result.stdout.is_empty() {
        callback("stdout", &result.stdout);
    }
    if !result.stderr.is_empty() {
        callback("stderr", &result.stderr);
    }
    result
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
    if spec.stdin_text.is_some() {
        command.stdin(Stdio::piped());
    }
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

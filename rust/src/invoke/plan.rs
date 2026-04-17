use crate::exec::{CommandSpec, Runner};
use crate::output::{parse_transcript_for_runner, schema_name_for_runner, Transcript};
use crate::parser::{parse_args, resolve_command, resolve_output_mode, CccConfig};
use std::error::Error as StdError;
use std::fmt;
use std::path::Path;

use super::request::{OutputMode, Request, RunnerKind};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Plan {
    command_spec: CommandSpec,
    runner: RunnerKind,
    output_mode: OutputMode,
    warnings: Vec<String>,
}

impl Plan {
    pub fn command_spec(&self) -> &CommandSpec {
        &self.command_spec
    }

    pub fn runner(&self) -> RunnerKind {
        self.runner
    }

    pub fn output_mode(&self) -> OutputMode {
        self.output_mode
    }

    pub fn warnings(&self) -> &[String] {
        &self.warnings
    }
}

#[derive(Debug)]
pub enum Error {
    InvalidRequest(String),
    Config(String),
    Spawn(std::io::Error),
    ToolFailed { exit_code: i32, stderr: String },
    OutputParse(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::InvalidRequest(message) => write!(f, "invalid request: {message}"),
            Error::Config(message) => write!(f, "configuration error: {message}"),
            Error::Spawn(error) => write!(f, "spawn error: {error}"),
            Error::ToolFailed { exit_code, stderr } => {
                write!(f, "tool failed with exit code {exit_code}: {stderr}")
            }
            Error::OutputParse(message) => write!(f, "output parse error: {message}"),
        }
    }
}

impl StdError for Error {}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Self::Spawn(error)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Run {
    plan: Plan,
    exit_code: i32,
    stdout: String,
    stderr: String,
    parsed_output: Option<Transcript>,
}

impl Run {
    pub fn plan(&self) -> &Plan {
        &self.plan
    }

    pub fn exit_code(&self) -> i32 {
        self.exit_code
    }

    pub fn stdout(&self) -> &str {
        &self.stdout
    }

    pub fn stderr(&self) -> &str {
        &self.stderr
    }

    pub fn parsed_output(&self) -> Option<&Transcript> {
        self.parsed_output.as_ref()
    }

    pub fn final_text(&self) -> &str {
        self.parsed_output
            .as_ref()
            .map(|output| output.final_text.as_str())
            .unwrap_or(self.stdout.as_str())
    }
}

pub struct Client {
    config: Option<CccConfig>,
    runner: Runner,
}

impl Client {
    pub fn new() -> Self {
        Self {
            config: None,
            runner: Runner::new(),
        }
    }

    pub fn with_config(mut self, config: CccConfig) -> Self {
        self.config = Some(config);
        self
    }

    pub fn with_runtime_runner(mut self, runner: Runner) -> Self {
        self.runner = runner;
        self
    }

    pub fn plan(&self, request: &Request) -> Result<Plan, Error> {
        let argv = request.to_cli_tokens();
        let parsed = parse_args(&argv);
        let config = self.config.clone().unwrap_or_default();
        let (argv, env, warnings) = resolve_command(&parsed, Some(&config))
            .map_err(|message| Error::Config(message.to_string()))?;
        let output_mode = resolve_output_mode(&parsed, Some(&config))
            .map_err(|message| Error::Config(message.to_string()))
            .and_then(|mode| {
                OutputMode::from_cli_value(&mode)
                    .ok_or_else(|| Error::Config("resolved output mode was not recognized".into()))
            })?;
        let runner = runner_kind_from_argv(&argv)
            .or_else(|| request.runner_kind())
            .unwrap_or(RunnerKind::OpenCode);
        Ok(Plan {
            command_spec: CommandSpec {
                argv,
                stdin_text: None,
                cwd: None,
                env,
            },
            runner,
            output_mode,
            warnings,
        })
    }

    pub fn run(&self, request: &Request) -> Result<Run, Error> {
        let plan = self.plan(request)?;
        let completed = self.runner.run(plan.command_spec().clone());
        let parsed_output = if should_parse_output_mode(plan.output_mode()) {
            if schema_name_for_runner(plan.runner()).is_some() {
                parse_transcript_for_runner(&completed.stdout, plan.runner())
            } else {
                None
            }
        } else {
            None
        };

        if completed.exit_code != 0 {
            return Err(Error::ToolFailed {
                exit_code: completed.exit_code,
                stderr: completed.stderr,
            });
        }

        Ok(Run {
            plan,
            exit_code: completed.exit_code,
            stdout: completed.stdout,
            stderr: completed.stderr,
            parsed_output,
        })
    }
}

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
}

fn should_parse_output_mode(output_mode: OutputMode) -> bool {
    matches!(
        output_mode,
        OutputMode::Json
            | OutputMode::StreamJson
            | OutputMode::Formatted
            | OutputMode::StreamFormatted
    )
}

fn runner_kind_from_argv(argv: &[String]) -> Option<RunnerKind> {
    let binary = argv.first()?;
    let name = Path::new(binary)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(binary.as_str());
    match name {
        "opencode" => Some(RunnerKind::OpenCode),
        "claude" => Some(RunnerKind::Claude),
        "codex" => Some(RunnerKind::Codex),
        "kimi" => Some(RunnerKind::Kimi),
        "cursor-agent" => Some(RunnerKind::Cursor),
        "gemini" => Some(RunnerKind::Gemini),
        "roocode" => Some(RunnerKind::RooCode),
        "crush" => Some(RunnerKind::Crush),
        _ => None,
    }
}

use crate::exec::CommandSpec;
use crate::parser::{parse_args, resolve_command, resolve_output_mode, CccConfig};
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

pub struct Client {
    config: Option<CccConfig>,
}

impl Client {
    pub fn new() -> Self {
        Self { config: None }
    }

    pub fn with_config(mut self, config: CccConfig) -> Self {
        self.config = Some(config);
        self
    }

    pub fn plan(&self, request: &Request) -> Result<Plan, String> {
        let argv = request.to_cli_tokens();
        let parsed = parse_args(&argv);
        let config = self.config.clone().unwrap_or_default();
        let (argv, env, warnings) = resolve_command(&parsed, Some(&config))?;
        let output_mode = resolve_output_mode(&parsed, Some(&config))
            .ok()
            .and_then(|mode| OutputMode::from_cli_value(&mode))
            .ok_or_else(|| "resolved output mode was not recognized".to_string())?;
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
}

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
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

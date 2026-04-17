#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum RunnerKind {
    OpenCode,
    Claude,
    Codex,
    Kimi,
    Cursor,
    Gemini,
    RooCode,
    Crush,
}

impl RunnerKind {
    pub(crate) fn from_cli_token(token: &str) -> Option<Self> {
        match token {
            "oc" | "opencode" => Some(RunnerKind::OpenCode),
            "cc" | "claude" => Some(RunnerKind::Claude),
            "c" | "cx" | "codex" => Some(RunnerKind::Codex),
            "k" | "kimi" => Some(RunnerKind::Kimi),
            "cu" | "cursor" => Some(RunnerKind::Cursor),
            "g" | "gemini" => Some(RunnerKind::Gemini),
            "rc" | "roocode" => Some(RunnerKind::RooCode),
            "cr" | "crush" => Some(RunnerKind::Crush),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputMode {
    Text,
    StreamText,
    Json,
    StreamJson,
    Formatted,
    StreamFormatted,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Request {
    prompt: String,
    prompt_supplied: bool,
    runner: Option<RunnerKind>,
    agent: Option<String>,
    thinking: Option<i32>,
    show_thinking: Option<bool>,
    sanitize_osc: Option<bool>,
    permission_mode: Option<String>,
    save_session: bool,
    cleanup_session: bool,
    provider: Option<String>,
    model: Option<String>,
    output_mode: Option<OutputMode>,
    timeout_secs: Option<u64>,
}

impl Request {
    pub fn new(prompt: impl Into<String>) -> Self {
        Self {
            prompt: prompt.into(),
            prompt_supplied: true,
            runner: None,
            agent: None,
            thinking: None,
            show_thinking: None,
            sanitize_osc: None,
            permission_mode: None,
            save_session: false,
            cleanup_session: false,
            provider: None,
            model: None,
            output_mode: None,
            timeout_secs: None,
        }
    }

    pub fn with_runner(mut self, runner: RunnerKind) -> Self {
        self.runner = Some(runner);
        self
    }

    pub fn with_provider(mut self, provider: impl Into<String>) -> Self {
        self.provider = Some(provider.into());
        self
    }

    pub fn with_agent(mut self, agent: impl Into<String>) -> Self {
        self.agent = Some(agent.into());
        self
    }

    pub fn with_thinking(mut self, thinking: i32) -> Self {
        self.thinking = Some(thinking);
        self
    }

    pub fn with_show_thinking(mut self, enabled: bool) -> Self {
        self.show_thinking = Some(enabled);
        self
    }

    pub fn with_sanitize_osc(mut self, enabled: bool) -> Self {
        self.sanitize_osc = Some(enabled);
        self
    }

    pub fn with_permission_mode(mut self, mode: impl Into<String>) -> Self {
        self.permission_mode = Some(mode.into());
        self
    }

    pub fn with_save_session(mut self, enabled: bool) -> Self {
        self.save_session = enabled;
        self
    }

    pub fn with_cleanup_session(mut self, enabled: bool) -> Self {
        self.cleanup_session = enabled;
        self
    }

    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = Some(model.into());
        self
    }

    pub fn with_output_mode(mut self, output_mode: OutputMode) -> Self {
        self.output_mode = Some(output_mode);
        self
    }

    pub fn with_timeout_secs(mut self, secs: u64) -> Self {
        self.timeout_secs = Some(secs);
        self
    }

    pub fn timeout_secs(&self) -> Option<u64> {
        self.timeout_secs
    }

    pub fn prompt(&self) -> &str {
        &self.prompt
    }

    pub fn runner(&self) -> Option<RunnerKind> {
        self.runner
    }

    pub fn provider(&self) -> Option<&str> {
        self.provider.as_deref()
    }

    pub fn model(&self) -> Option<&str> {
        self.model.as_deref()
    }

    pub fn output_mode(&self) -> Option<OutputMode> {
        self.output_mode
    }

    pub(crate) fn prompt_text(&self) -> &str {
        &self.prompt
    }

    pub(crate) fn runner_kind(&self) -> Option<RunnerKind> {
        self.runner
    }

    pub(crate) fn provider_text(&self) -> Option<&str> {
        self.provider.as_deref()
    }

    pub(crate) fn model_text(&self) -> Option<&str> {
        self.model.as_deref()
    }

    pub(crate) fn output_mode_kind(&self) -> Option<OutputMode> {
        self.output_mode
    }

    pub(crate) fn from_parsed_args(parsed: &crate::parser::ParsedArgs) -> Result<Self, String> {
        let runner = parsed
            .runner
            .as_deref()
            .and_then(RunnerKind::from_cli_token);
        if parsed.runner.is_some() && runner.is_none() {
            return Err("unknown runner selector".to_string());
        }

        let output_mode = match parsed.output_mode.as_deref() {
            Some("") => {
                return Err(
                    "output mode requires one of: text, stream-text, json, stream-json, formatted, stream-formatted"
                        .to_string(),
                )
            }
            Some(value) => Some(OutputMode::from_cli_value(value).ok_or_else(|| {
                "output mode must be one of: text, stream-text, json, stream-json, formatted, stream-formatted"
                    .to_string()
            })?),
            None => None,
        };

        Ok(Self {
            prompt: parsed.prompt.clone(),
            prompt_supplied: parsed.prompt_supplied,
            runner,
            agent: parsed.alias.clone(),
            thinking: parsed.thinking,
            show_thinking: parsed.show_thinking,
            sanitize_osc: parsed.sanitize_osc,
            permission_mode: parsed.permission_mode.clone(),
            save_session: parsed.save_session,
            cleanup_session: parsed.cleanup_session,
            provider: parsed.provider.clone(),
            model: parsed.model.clone(),
            output_mode,
            timeout_secs: parsed.timeout_secs,
        })
    }

    pub(crate) fn to_cli_tokens(&self) -> Vec<String> {
        let mut tokens = Vec::new();
        if let Some(runner) = self.runner_kind() {
            tokens.push(runner.as_cli_token().to_string());
        }
        if let Some(thinking) = self.thinking {
            tokens.push(format!("+{thinking}"));
        }
        if let Some(show_thinking) = self.show_thinking {
            tokens.push(if show_thinking {
                "--show-thinking".to_string()
            } else {
                "--no-show-thinking".to_string()
            });
        }
        if let Some(sanitize_osc) = self.sanitize_osc {
            tokens.push(if sanitize_osc {
                "--sanitize-osc".to_string()
            } else {
                "--no-sanitize-osc".to_string()
            });
        }
        if let Some(permission_mode) = self.permission_mode.as_deref() {
            tokens.push("--permission-mode".to_string());
            tokens.push(permission_mode.to_string());
        }
        if self.save_session {
            tokens.push("--save-session".to_string());
        }
        if self.cleanup_session {
            tokens.push("--cleanup-session".to_string());
        }
        if let Some(agent) = self.agent.as_deref() {
            tokens.push(format!("@{agent}"));
        }
        if let Some(provider) = self.provider_text() {
            if let Some(model) = self.model_text() {
                tokens.push(format!(":{provider}:{model}"));
            }
        } else if let Some(model) = self.model_text() {
            tokens.push(format!(":{model}"));
        }
        if let Some(output_mode) = self.output_mode_kind() {
            tokens.push("--output-mode".to_string());
            tokens.push(output_mode.as_cli_value().to_string());
        }
        if let Some(timeout) = self.timeout_secs {
            tokens.push("--timeout-secs".to_string());
            tokens.push(timeout.to_string());
        }
        if self.prompt_supplied {
            tokens.push(self.prompt_text().to_string());
        }
        tokens
    }
}

impl RunnerKind {
    pub(crate) fn as_cli_token(self) -> &'static str {
        match self {
            RunnerKind::OpenCode => "oc",
            RunnerKind::Claude => "cc",
            RunnerKind::Codex => "c",
            RunnerKind::Kimi => "k",
            RunnerKind::Cursor => "cu",
            RunnerKind::Gemini => "g",
            RunnerKind::RooCode => "rc",
            RunnerKind::Crush => "cr",
        }
    }
}

impl OutputMode {
    pub(crate) fn as_cli_value(self) -> &'static str {
        match self {
            OutputMode::Text => "text",
            OutputMode::StreamText => "stream-text",
            OutputMode::Json => "json",
            OutputMode::StreamJson => "stream-json",
            OutputMode::Formatted => "formatted",
            OutputMode::StreamFormatted => "stream-formatted",
        }
    }

    pub(crate) fn from_cli_value(value: &str) -> Option<Self> {
        match value {
            "text" => Some(OutputMode::Text),
            "stream-text" => Some(OutputMode::StreamText),
            "json" => Some(OutputMode::Json),
            "stream-json" => Some(OutputMode::StreamJson),
            "formatted" => Some(OutputMode::Formatted),
            "stream-formatted" => Some(OutputMode::StreamFormatted),
            _ => None,
        }
    }
}

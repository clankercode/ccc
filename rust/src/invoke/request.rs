#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
    runner: Option<RunnerKind>,
    model: Option<String>,
    output_mode: Option<OutputMode>,
}

impl Request {
    pub fn new(prompt: impl Into<String>) -> Self {
        Self {
            prompt: prompt.into(),
            runner: None,
            model: None,
            output_mode: None,
        }
    }

    pub fn with_runner(mut self, runner: RunnerKind) -> Self {
        self.runner = Some(runner);
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

    pub fn prompt(&self) -> &str {
        &self.prompt
    }

    pub fn runner(&self) -> Option<RunnerKind> {
        self.runner
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

    pub(crate) fn model_text(&self) -> Option<&str> {
        self.model.as_deref()
    }

    pub(crate) fn output_mode_kind(&self) -> Option<OutputMode> {
        self.output_mode
    }

    pub(crate) fn to_cli_tokens(&self) -> Vec<String> {
        let mut tokens = Vec::new();
        if let Some(runner) = self.runner_kind() {
            tokens.push(runner.as_cli_token().to_string());
        }
        if let Some(model) = self.model_text() {
            tokens.push(format!(":{model}"));
        }
        if let Some(output_mode) = self.output_mode_kind() {
            tokens.push("--output-mode".to_string());
            tokens.push(output_mode.as_cli_value().to_string());
        }
        if !self.prompt_text().trim().is_empty() {
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

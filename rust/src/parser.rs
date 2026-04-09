use std::collections::BTreeMap;
use std::sync::LazyLock;
use std::sync::RwLock;

const PERMISSION_MODES: &[&str] = &["safe", "auto", "yolo", "plan"];

#[derive(Clone, Debug)]
pub struct RunnerInfo {
    pub binary: String,
    pub extra_args: Vec<String>,
    pub thinking_flags: BTreeMap<i32, Vec<String>>,
    pub show_thinking_flags: BTreeMap<bool, Vec<String>>,
    pub yolo_flags: Vec<String>,
    pub provider_flag: String,
    pub model_flag: String,
    pub agent_flag: String,
    pub prompt_flag: String,
}

#[derive(Clone, Debug, Default)]
pub struct ParsedArgs {
    pub runner: Option<String>,
    pub thinking: Option<i32>,
    pub show_thinking: Option<bool>,
    pub yolo: bool,
    pub permission_mode: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub alias: Option<String>,
    pub prompt: String,
}

#[derive(Clone, Debug)]
pub struct AliasDef {
    pub runner: Option<String>,
    pub thinking: Option<i32>,
    pub show_thinking: Option<bool>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub agent: Option<String>,
}

impl Default for AliasDef {
    fn default() -> Self {
        Self {
            runner: None,
            thinking: None,
            show_thinking: None,
            provider: None,
            model: None,
            agent: None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CccConfig {
    pub default_runner: String,
    pub default_provider: String,
    pub default_model: String,
    pub default_thinking: Option<i32>,
    pub default_show_thinking: bool,
    pub aliases: BTreeMap<String, AliasDef>,
    pub abbreviations: BTreeMap<String, String>,
}

impl Default for CccConfig {
    fn default() -> Self {
        Self {
            default_runner: "oc".to_string(),
            default_provider: String::new(),
            default_model: String::new(),
            default_thinking: None,
            default_show_thinking: false,
            aliases: BTreeMap::new(),
            abbreviations: BTreeMap::new(),
        }
    }
}

pub static RUNNER_REGISTRY: LazyLock<RwLock<BTreeMap<String, RunnerInfo>>> = LazyLock::new(|| {
    let mut m = BTreeMap::new();
    let opencode = RunnerInfo {
        binary: "opencode".into(),
        extra_args: vec!["run".into()],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: {
            let mut tf = BTreeMap::new();
            tf.insert(true, vec!["--thinking".into()]);
            tf
        },
        yolo_flags: vec![],
        provider_flag: String::new(),
        model_flag: String::new(),
        agent_flag: "--agent".into(),
        prompt_flag: String::new(),
    };
    let claude = RunnerInfo {
        binary: "claude".into(),
        extra_args: vec!["-p".into()],
        thinking_flags: {
            let mut tf = BTreeMap::new();
            tf.insert(0, vec!["--thinking".into(), "disabled".into()]);
            tf.insert(
                1,
                vec![
                    "--thinking".into(),
                    "enabled".into(),
                    "--effort".into(),
                    "low".into(),
                ],
            );
            tf.insert(
                2,
                vec![
                    "--thinking".into(),
                    "enabled".into(),
                    "--effort".into(),
                    "medium".into(),
                ],
            );
            tf.insert(
                3,
                vec![
                    "--thinking".into(),
                    "enabled".into(),
                    "--effort".into(),
                    "high".into(),
                ],
            );
            tf.insert(
                4,
                vec![
                    "--thinking".into(),
                    "enabled".into(),
                    "--effort".into(),
                    "max".into(),
                ],
            );
            tf
        },
        show_thinking_flags: {
            let mut tf = BTreeMap::new();
            tf.insert(
                true,
                vec![
                    "--thinking".into(),
                    "enabled".into(),
                    "--effort".into(),
                    "low".into(),
                ],
            );
            tf
        },
        yolo_flags: vec!["--dangerously-skip-permissions".into()],
        provider_flag: String::new(),
        model_flag: "--model".into(),
        agent_flag: "--agent".into(),
        prompt_flag: String::new(),
    };
    let kimi = RunnerInfo {
        binary: "kimi".into(),
        extra_args: vec![],
        thinking_flags: {
            let mut tf = BTreeMap::new();
            tf.insert(0, vec!["--no-thinking".into()]);
            tf.insert(1, vec!["--thinking".into()]);
            tf.insert(2, vec!["--thinking".into()]);
            tf.insert(3, vec!["--thinking".into()]);
            tf.insert(4, vec!["--thinking".into()]);
            tf
        },
        show_thinking_flags: {
            let mut tf = BTreeMap::new();
            tf.insert(true, vec!["--thinking".into()]);
            tf
        },
        yolo_flags: vec!["--yolo".into()],
        provider_flag: String::new(),
        model_flag: "--model".into(),
        agent_flag: "--agent".into(),
        prompt_flag: "--prompt".into(),
    };
    let codex = RunnerInfo {
        binary: "codex".into(),
        extra_args: vec!["exec".into()],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: BTreeMap::new(),
        yolo_flags: vec!["--dangerously-bypass-approvals-and-sandbox".into()],
        provider_flag: String::new(),
        model_flag: "--model".into(),
        agent_flag: String::new(),
        prompt_flag: String::new(),
    };
    let roocode = RunnerInfo {
        binary: "roocode".into(),
        extra_args: vec![],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: BTreeMap::new(),
        yolo_flags: vec![],
        provider_flag: String::new(),
        model_flag: String::new(),
        agent_flag: String::new(),
        prompt_flag: String::new(),
    };
    let crush = RunnerInfo {
        binary: "crush".into(),
        extra_args: vec!["run".into()],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: BTreeMap::new(),
        yolo_flags: vec![],
        provider_flag: String::new(),
        model_flag: String::new(),
        agent_flag: String::new(),
        prompt_flag: String::new(),
    };

    let claude_clone = claude.clone();
    let kimi_clone = kimi.clone();
    let opencode_clone = opencode.clone();

    let codex_clone = codex.clone();
    let roocode_clone = roocode.clone();
    let crush_clone = crush.clone();

    m.insert("opencode".into(), opencode);
    m.insert("claude".into(), claude);
    m.insert("kimi".into(), kimi);
    m.insert("codex".into(), codex);
    m.insert("roocode".into(), roocode);
    m.insert("crush".into(), crush);

    m.insert("oc".into(), opencode_clone);
    m.insert("cc".into(), claude_clone.clone());
    m.insert("c".into(), codex_clone.clone());
    m.insert("cx".into(), codex_clone);
    m.insert("k".into(), kimi_clone);
    m.insert("rc".into(), roocode_clone.clone());
    m.insert("cr".into(), crush_clone);

    RwLock::new(m)
});

static RUNNER_SELECTOR_STRS: &[&str] = &[
    "oc", "cc", "c", "cx", "k", "rc", "cr", "codex", "claude", "opencode", "kimi", "roocode",
    "crush", "pi",
];

fn is_runner_selector(s: &str) -> bool {
    RUNNER_SELECTOR_STRS
        .iter()
        .any(|&sel| sel.eq_ignore_ascii_case(s))
}

fn parse_thinking(s: &str) -> Option<i32> {
    let rest = s.strip_prefix('+')?;
    let n: i32 = rest.parse().ok()?;
    if (0..=4).contains(&n) {
        Some(n)
    } else {
        None
    }
}

fn parse_provider_model(s: &str) -> Option<(&str, &str)> {
    let rest = s.strip_prefix(':')?;
    let parts: Vec<&str> = rest.splitn(2, ':').collect();
    if parts.len() == 2 {
        Some((parts[0], parts[1]))
    } else {
        None
    }
}

fn parse_model_only(s: &str) -> Option<&str> {
    let rest = s.strip_prefix(':')?;
    if rest.contains(':') {
        None
    } else {
        Some(rest)
    }
}

fn parse_alias(s: &str) -> Option<&str> {
    let rest = s.strip_prefix('@')?;
    if rest
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        Some(rest)
    } else {
        None
    }
}

pub fn parse_args(argv: &[String]) -> ParsedArgs {
    let mut parsed = ParsedArgs::default();
    let mut positional: Vec<String> = Vec::new();
    let mut force_prompt = false;
    let mut index = 0;

    while index < argv.len() {
        let token = &argv[index];
        if force_prompt || !positional.is_empty() {
            positional.push(token.clone());
        } else if token == "--" {
            force_prompt = true;
            index += 1;
            continue;
        } else if is_runner_selector(token) {
            parsed.runner = Some(token.to_lowercase());
        } else if let Some(level) = parse_thinking(token) {
            parsed.thinking = Some(level);
        } else if token == "--show-thinking" || token == "--no-show-thinking" {
            parsed.show_thinking = Some(token == "--show-thinking");
        } else if token == "--yolo" || token == "-y" {
            parsed.yolo = true;
            parsed.permission_mode = Some("yolo".to_string());
        } else if token == "--permission-mode" {
            if index + 1 >= argv.len() {
                parsed.permission_mode = Some(String::new());
            } else {
                let mode = argv[index + 1].to_lowercase();
                parsed.yolo = mode == "yolo";
                parsed.permission_mode = Some(mode);
                index += 1;
            }
        } else if let Some((provider, model)) = parse_provider_model(token) {
            parsed.provider = Some(provider.to_string());
            parsed.model = Some(model.to_string());
        } else if let Some(model) = parse_model_only(token) {
            parsed.model = Some(model.to_string());
        } else if let Some(alias_name) = parse_alias(token) {
            parsed.alias = Some(alias_name.to_string());
        } else {
            positional.push(token.clone());
        }
        index += 1;
    }

    parsed.prompt = positional.join(" ");
    parsed
}

pub fn resolve_command(
    parsed: &ParsedArgs,
    config: Option<&CccConfig>,
) -> Result<(Vec<String>, BTreeMap<String, String>, Vec<String>), &'static str> {
    let config = config.cloned().unwrap_or_default();
    let registry = RUNNER_REGISTRY.read().unwrap();
    let mut warnings = Vec::new();

    let runner_name = parsed.runner.as_deref().unwrap_or(&config.default_runner);
    let resolved_name = config
        .abbreviations
        .get(runner_name)
        .map(|s| s.as_str())
        .unwrap_or(runner_name);

    let info = registry
        .get(resolved_name)
        .or_else(|| registry.get(&config.default_runner))
        .or_else(|| registry.get("opencode"))
        .ok_or("no runner found")?;

    let alias_def = parsed.alias.as_ref().and_then(|a| config.aliases.get(a));
    let mut effective_runner_name = resolved_name.to_string();

    let effective_runner = if let Some(alias_def) = alias_def {
        if parsed.runner.is_none() {
            if let Some(alias_runner) = alias_def.runner.as_deref() {
                let resolved = config
                    .abbreviations
                    .get(alias_runner)
                    .map(|s| s.as_str())
                    .unwrap_or(alias_runner);
                effective_runner_name = resolved.to_string();
                registry.get(resolved).unwrap_or(info)
            } else {
                info
            }
        } else {
            info
        }
    } else {
        info
    };

    let mut argv: Vec<String> = vec![effective_runner.binary.clone()];
    argv.extend(effective_runner.extra_args.iter().cloned());

    let effective_thinking = parsed
        .thinking
        .or_else(|| alias_def.and_then(|a| a.thinking))
        .or(config.default_thinking);

    if let Some(level) = effective_thinking {
        if let Some(flags) = effective_runner.thinking_flags.get(&level) {
            argv.extend(flags.iter().cloned());
        }
    }

    let effective_show_thinking = parsed
        .show_thinking
        .or_else(|| alias_def.and_then(|a| a.show_thinking))
        .unwrap_or(config.default_show_thinking);

    if effective_thinking.is_none() && effective_show_thinking {
        if let Some(flags) = effective_runner.show_thinking_flags.get(&true) {
            argv.extend(flags.iter().cloned());
        }
    }

    let effective_provider: Option<String> = parsed
        .provider
        .clone()
        .or_else(|| alias_def.and_then(|a| a.provider.clone()))
        .or_else(|| {
            if config.default_provider.is_empty() {
                None
            } else {
                Some(config.default_provider.clone())
            }
        });

    let effective_model: Option<String> = parsed
        .model
        .clone()
        .or_else(|| alias_def.and_then(|a| a.model.clone()))
        .or_else(|| {
            if config.default_model.is_empty() {
                None
            } else {
                Some(config.default_model.clone())
            }
        });

    let mut env_overrides = BTreeMap::new();
    if let Some(ref provider) = effective_provider {
        env_overrides.insert("CCC_PROVIDER".to_string(), provider.clone());
    }

    if let Some(ref model) = effective_model {
        if !effective_runner.model_flag.is_empty() {
            argv.push(effective_runner.model_flag.clone());
            argv.push(model.clone());
        }
    }

    let effective_agent = if let Some(alias_def) = alias_def {
        alias_def.agent.clone()
    } else {
        parsed.alias.clone()
    };

    if let Some(agent) = effective_agent {
        if effective_runner.agent_flag.is_empty() {
            warnings.push(format!(
                "warning: runner \"{}\" does not support agents; ignoring @{}",
                effective_runner_name, agent
            ));
        } else {
            argv.push(effective_runner.agent_flag.clone());
            argv.push(agent);
        }
    }

    let effective_permission_mode = parsed.permission_mode.clone().or_else(|| {
        if parsed.yolo {
            Some("yolo".to_string())
        } else {
            None
        }
    });
    if let Some(ref mode) = effective_permission_mode {
        if mode.is_empty() {
            return Err("permission mode requires one of: safe, auto, yolo, plan");
        }
        if !PERMISSION_MODES.iter().any(|known| known == mode) {
            return Err("permission mode must be one of: safe, auto, yolo, plan");
        }
    }

    if matches!(effective_permission_mode.as_deref(), Some("safe")) {
        if matches!(effective_runner_name.as_str(), "cc" | "claude") {
            argv.push("--permission-mode".to_string());
            argv.push("default".to_string());
        }
    } else if matches!(effective_permission_mode.as_deref(), Some("auto")) {
        if matches!(effective_runner_name.as_str(), "cc" | "claude") {
            argv.push("--permission-mode".to_string());
            argv.push("auto".to_string());
        } else if matches!(effective_runner_name.as_str(), "c" | "cx" | "codex") {
            argv.push("--full-auto".to_string());
        } else {
            warnings.push(format!(
                "warning: runner \"{}\" does not support permission mode \"auto\"; ignoring it",
                effective_runner_name
            ));
        }
    } else if matches!(effective_permission_mode.as_deref(), Some("yolo")) {
        if !effective_runner.yolo_flags.is_empty() {
            argv.extend(effective_runner.yolo_flags.iter().cloned());
        } else if matches!(effective_runner_name.as_str(), "oc" | "opencode") {
            env_overrides.insert(
                "OPENCODE_CONFIG_CONTENT".to_string(),
                "{\"permission\":\"allow\"}".to_string(),
            );
        } else if matches!(effective_runner_name.as_str(), "cr" | "crush") {
            warnings.push(
                "warning: runner \"crush\" does not support yolo mode in non-interactive run mode; ignoring --yolo".to_string(),
            );
        } else if matches!(effective_runner_name.as_str(), "rc" | "roocode") {
            warnings.push("warning: runner \"roocode\" yolo mode is unverified; ignoring --yolo".to_string());
        }
    } else if matches!(effective_permission_mode.as_deref(), Some("plan")) {
        if matches!(effective_runner_name.as_str(), "cc" | "claude") {
            argv.push("--permission-mode".to_string());
            argv.push("plan".to_string());
        } else if matches!(effective_runner_name.as_str(), "k" | "kimi") {
            argv.push("--plan".to_string());
        } else {
            warnings.push(format!(
                "warning: runner \"{}\" does not support permission mode \"plan\"; ignoring it",
                effective_runner_name
            ));
        }
    }

    let prompt = parsed.prompt.trim();
    if prompt.is_empty() {
        return Err("prompt must not be empty");
    }
    if effective_runner.prompt_flag.is_empty() {
        argv.push(prompt.to_string());
    } else {
        argv.push(effective_runner.prompt_flag.clone());
        argv.push(prompt.to_string());
    }

    Ok((argv, env_overrides, warnings))
}

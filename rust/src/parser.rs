use std::collections::BTreeMap;
use std::sync::LazyLock;
use std::sync::RwLock;

const PERMISSION_MODES: &[&str] = &["safe", "auto", "yolo", "plan"];
const PROMPT_MODES: &[&str] = &["default", "prepend", "append"];
const OUTPUT_MODES: &[&str] = &[
    "text",
    "stream-text",
    "json",
    "stream-json",
    "formatted",
    "stream-formatted",
];

#[derive(Clone, Debug)]
pub struct RunnerInfo {
    pub binary: String,
    pub extra_args: Vec<String>,
    pub no_persist_flags: Vec<String>,
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
    pub print_config: bool,
    pub sanitize_osc: Option<bool>,
    pub output_mode: Option<String>,
    pub forward_unknown_json: bool,
    pub save_session: bool,
    pub cleanup_session: bool,
    pub yolo: bool,
    pub permission_mode: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub alias: Option<String>,
    pub prompt: String,
    pub prompt_supplied: bool,
}

#[derive(Clone, Debug)]
pub struct AliasDef {
    pub runner: Option<String>,
    pub thinking: Option<i32>,
    pub show_thinking: Option<bool>,
    pub sanitize_osc: Option<bool>,
    pub output_mode: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub agent: Option<String>,
    pub prompt: Option<String>,
    pub prompt_mode: Option<String>,
}

impl Default for AliasDef {
    fn default() -> Self {
        Self {
            runner: None,
            thinking: None,
            show_thinking: None,
            sanitize_osc: None,
            output_mode: None,
            provider: None,
            model: None,
            agent: None,
            prompt: None,
            prompt_mode: None,
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
    pub default_sanitize_osc: Option<bool>,
    pub default_output_mode: String,
    pub aliases: BTreeMap<String, AliasDef>,
    pub abbreviations: BTreeMap<String, String>,
}

impl Default for CccConfig {
    fn default() -> Self {
        Self {
            default_runner: "oc".to_string(),
            default_provider: String::new(),
            default_model: String::new(),
            default_thinking: Some(1),
            default_show_thinking: true,
            default_sanitize_osc: None,
            default_output_mode: "text".to_string(),
            aliases: BTreeMap::new(),
            abbreviations: BTreeMap::new(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OutputPlan {
    pub runner_name: String,
    pub mode: String,
    pub stream: bool,
    pub formatted: bool,
    pub schema: Option<String>,
    pub argv_flags: Vec<String>,
    pub warnings: Vec<String>,
}

pub static RUNNER_REGISTRY: LazyLock<RwLock<BTreeMap<String, RunnerInfo>>> = LazyLock::new(|| {
    let mut m = BTreeMap::new();
    let opencode = RunnerInfo {
        binary: "opencode".into(),
        extra_args: vec!["run".into()],
        no_persist_flags: vec![],
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
        no_persist_flags: vec!["--no-session-persistence".into()],
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
        no_persist_flags: vec![],
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
        no_persist_flags: vec!["--ephemeral".into()],
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
        no_persist_flags: vec![],
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
        no_persist_flags: vec![],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: BTreeMap::new(),
        yolo_flags: vec![],
        provider_flag: String::new(),
        model_flag: String::new(),
        agent_flag: String::new(),
        prompt_flag: String::new(),
    };
    let cursor = RunnerInfo {
        binary: "cursor-agent".into(),
        extra_args: vec!["--print".into(), "--trust".into()],
        no_persist_flags: vec![],
        thinking_flags: BTreeMap::new(),
        show_thinking_flags: BTreeMap::new(),
        yolo_flags: vec!["--yolo".into()],
        provider_flag: String::new(),
        model_flag: "--model".into(),
        agent_flag: String::new(),
        prompt_flag: String::new(),
    };

    let claude_clone = claude.clone();
    let kimi_clone = kimi.clone();
    let opencode_clone = opencode.clone();

    let codex_clone = codex.clone();
    let roocode_clone = roocode.clone();
    let crush_clone = crush.clone();
    let cursor_clone = cursor.clone();

    m.insert("opencode".into(), opencode);
    m.insert("claude".into(), claude);
    m.insert("kimi".into(), kimi);
    m.insert("codex".into(), codex);
    m.insert("roocode".into(), roocode);
    m.insert("crush".into(), crush);
    m.insert("cursor".into(), cursor);

    m.insert("oc".into(), opencode_clone);
    m.insert("cc".into(), claude_clone.clone());
    m.insert("c".into(), codex_clone.clone());
    m.insert("cx".into(), codex_clone);
    m.insert("k".into(), kimi_clone);
    m.insert("rc".into(), roocode_clone.clone());
    m.insert("cr".into(), crush_clone);
    m.insert("cu".into(), cursor_clone);

    RwLock::new(m)
});

static RUNNER_SELECTOR_STRS: &[&str] = &[
    "oc", "cc", "c", "cx", "k", "rc", "cr", "cu", "codex", "claude", "opencode", "kimi", "roocode",
    "crush", "cursor", "pi",
];

fn is_runner_selector(s: &str) -> bool {
    RUNNER_SELECTOR_STRS
        .iter()
        .any(|&sel| sel.eq_ignore_ascii_case(s))
}

fn parse_thinking(s: &str) -> Option<i32> {
    let rest = s.strip_prefix('+')?;
    match rest.to_ascii_lowercase().as_str() {
        "0" | "none" => Some(0),
        "1" | "low" => Some(1),
        "2" | "med" | "mid" | "medium" => Some(2),
        "3" | "high" => Some(3),
        "4" | "max" | "xhigh" => Some(4),
        _ => None,
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

fn parse_output_mode(s: &str) -> Option<String> {
    let mode = s.to_ascii_lowercase();
    if OUTPUT_MODES.iter().any(|known| *known == mode) {
        Some(mode)
    } else {
        None
    }
}

fn parse_output_mode_sugar(s: &str) -> Option<String> {
    match s.to_ascii_lowercase().as_str() {
        ".text" => Some("text".to_string()),
        "..text" => Some("stream-text".to_string()),
        ".json" => Some("json".to_string()),
        "..json" => Some("stream-json".to_string()),
        ".fmt" => Some("formatted".to_string()),
        "..fmt" => Some("stream-formatted".to_string()),
        _ => None,
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
        } else if token == "--print-config" {
            parsed.print_config = true;
        } else if token == "--sanitize-osc" || token == "--no-sanitize-osc" {
            parsed.sanitize_osc = Some(token == "--sanitize-osc");
        } else if token == "--output-mode" || token == "-o" {
            if index + 1 >= argv.len() {
                parsed.output_mode = Some(String::new());
            } else {
                parsed.output_mode = Some(argv[index + 1].to_ascii_lowercase());
                index += 1;
            }
        } else if token == "--forward-unknown-json" {
            parsed.forward_unknown_json = true;
        } else if token == "--save-session" {
            parsed.save_session = true;
        } else if token == "--cleanup-session" {
            parsed.cleanup_session = true;
        } else if let Some(mode) = parse_output_mode_sugar(token) {
            parsed.output_mode = Some(mode);
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
    parsed.prompt_supplied = !positional.is_empty();
    parsed
}

pub fn resolve_command(
    parsed: &ParsedArgs,
    config: Option<&CccConfig>,
) -> Result<(Vec<String>, BTreeMap<String, String>, Vec<String>), String> {
    let config = config.cloned().unwrap_or_default();
    let registry = RUNNER_REGISTRY.read().unwrap();
    let mut warnings = Vec::new();

    let (effective_runner_name, effective_runner, alias_def) =
        resolve_effective_runner(parsed, &config, &registry)
            .ok_or_else(|| "no runner found".to_string())?;
    if parsed.save_session && parsed.cleanup_session {
        return Err("--save-session and --cleanup-session are mutually exclusive".to_string());
    }

    let mut argv: Vec<String> = vec![effective_runner.binary.clone()];
    argv.extend(effective_runner.extra_args.iter().cloned());
    warnings.extend(session_persistence_warnings(
        parsed,
        &effective_runner_name,
        effective_runner,
    ));
    let output_plan = resolve_output_plan(parsed, Some(&config)).map_err(str::to_string)?;
    warnings.extend(output_plan.warnings.clone());
    argv.extend(output_plan.argv_flags.iter().cloned());

    let effective_thinking = parsed
        .thinking
        .or_else(|| alias_def.and_then(|a| a.thinking))
        .or(config.default_thinking);

    let mut thinking_flags_applied = false;
    if let Some(level) = effective_thinking {
        if let Some(flags) = effective_runner.thinking_flags.get(&level) {
            argv.extend(flags.iter().cloned());
            thinking_flags_applied = true;
        }
    }

    let effective_show_thinking = resolve_show_thinking(parsed, Some(&config));

    if !thinking_flags_applied && effective_show_thinking {
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
    if matches!(effective_runner_name.as_str(), "oc" | "opencode") {
        env_overrides.insert(
            "OPENCODE_DISABLE_TERMINAL_TITLE".to_string(),
            "true".to_string(),
        );
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
            return Err("permission mode requires one of: safe, auto, yolo, plan".to_string());
        }
        if !PERMISSION_MODES.iter().any(|known| known == mode) {
            return Err("permission mode must be one of: safe, auto, yolo, plan".to_string());
        }
    }

    if matches!(effective_permission_mode.as_deref(), Some("safe")) {
        if matches!(effective_runner_name.as_str(), "cc" | "claude") {
            argv.push("--permission-mode".to_string());
            argv.push("default".to_string());
        } else if matches!(effective_runner_name.as_str(), "oc" | "opencode") {
            env_overrides.insert(
                "OPENCODE_CONFIG_CONTENT".to_string(),
                "{\"permission\":\"ask\"}".to_string(),
            );
        } else if matches!(effective_runner_name.as_str(), "cu" | "cursor") {
            argv.push("--sandbox".to_string());
            argv.push("enabled".to_string());
        } else if matches!(effective_runner_name.as_str(), "rc" | "roocode") {
            warnings.push(
                "warning: runner \"roocode\" safe mode is unverified; leaving default permissions unchanged"
                    .to_string(),
            );
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
            warnings.push(
                "warning: runner \"roocode\" yolo mode is unverified; ignoring --yolo".to_string(),
            );
        }
    } else if matches!(effective_permission_mode.as_deref(), Some("plan")) {
        if matches!(effective_runner_name.as_str(), "cc" | "claude") {
            argv.push("--permission-mode".to_string());
            argv.push("plan".to_string());
        } else if matches!(effective_runner_name.as_str(), "k" | "kimi") {
            argv.push("--plan".to_string());
        } else if matches!(effective_runner_name.as_str(), "cu" | "cursor") {
            argv.push("--mode".to_string());
            argv.push("plan".to_string());
        } else {
            warnings.push(format!(
                "warning: runner \"{}\" does not support permission mode \"plan\"; ignoring it",
                effective_runner_name
            ));
        }
    }

    if !parsed.save_session {
        argv.extend(effective_runner.no_persist_flags.iter().cloned());
    }

    let prompt = resolve_prompt(parsed, alias_def)?;
    if effective_runner.prompt_flag.is_empty() {
        argv.push(prompt);
    } else {
        argv.push(effective_runner.prompt_flag.clone());
        argv.push(prompt);
    }

    Ok((argv, env_overrides, warnings))
}

fn canonical_runner_name(effective_runner_name: &str, info: &RunnerInfo) -> String {
    match effective_runner_name {
        "oc" | "opencode" => "opencode".to_string(),
        "cc" | "claude" => "claude".to_string(),
        "c" | "cx" | "codex" => "codex".to_string(),
        "k" | "kimi" => "kimi".to_string(),
        "cr" | "crush" => "crush".to_string(),
        "rc" | "roocode" => "roocode".to_string(),
        "cu" | "cursor" => "cursor".to_string(),
        _ => info.binary.clone(),
    }
}

fn session_persistence_warnings(
    parsed: &ParsedArgs,
    effective_runner_name: &str,
    info: &RunnerInfo,
) -> Vec<String> {
    if parsed.save_session || !info.no_persist_flags.is_empty() {
        return Vec::new();
    }
    let display = canonical_runner_name(effective_runner_name, info);
    if parsed.cleanup_session {
        if display == "opencode" || display == "kimi" {
            return Vec::new();
        }
        return vec![format!(
            "warning: runner \"{display}\" does not support automatic session cleanup; pass --save-session to allow saved sessions explicitly"
        )];
    }
    Vec::new()
}

fn resolve_prompt(parsed: &ParsedArgs, alias_def: Option<&AliasDef>) -> Result<String, String> {
    let user_prompt = parsed.prompt.trim();
    let alias_prompt = alias_def
        .and_then(|alias| alias.prompt.as_deref())
        .map(str::trim)
        .unwrap_or("");
    let prompt_mode = alias_def
        .and_then(|alias| alias.prompt_mode.as_deref())
        .map(str::trim)
        .filter(|mode| !mode.is_empty())
        .unwrap_or("default");

    if !PROMPT_MODES.iter().any(|known| *known == prompt_mode) {
        return Err("prompt_mode must be one of: default, prepend, append".to_string());
    }

    if prompt_mode == "default" {
        let prompt = if user_prompt.is_empty() {
            alias_prompt
        } else {
            user_prompt
        };
        if prompt.is_empty() {
            return Err("prompt must not be empty".to_string());
        }
        return Ok(prompt.to_string());
    }

    if !parsed.prompt_supplied {
        return Err(format!(
            "prompt_mode {prompt_mode} requires an explicit prompt argument"
        ));
    }
    if alias_prompt.is_empty() {
        let alias_name = parsed.alias.as_deref().unwrap_or("<alias>");
        return Err(format!(
            "prompt_mode {prompt_mode} requires aliases.{alias_name}.prompt"
        ));
    }

    let mut parts = vec![alias_prompt, user_prompt];
    if prompt_mode == "append" {
        parts.reverse();
    }
    Ok(parts
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n"))
}

fn resolve_alias_def<'a>(parsed: &'a ParsedArgs, config: &'a CccConfig) -> Option<&'a AliasDef> {
    parsed
        .alias
        .as_ref()
        .and_then(|alias| config.aliases.get(alias))
}

fn resolve_runner_name(parsed_runner: Option<&str>, config: &CccConfig) -> String {
    let runner_name = parsed_runner.unwrap_or(&config.default_runner);
    config
        .abbreviations
        .get(runner_name)
        .cloned()
        .unwrap_or_else(|| runner_name.to_string())
}

fn resolve_effective_runner<'a>(
    parsed: &'a ParsedArgs,
    config: &'a CccConfig,
    registry: &'a BTreeMap<String, RunnerInfo>,
) -> Option<(String, &'a RunnerInfo, Option<&'a AliasDef>)> {
    let alias_def = resolve_alias_def(parsed, config);
    let mut runner_name = resolve_runner_name(parsed.runner.as_deref(), config);
    if parsed.runner.is_none() {
        if let Some(alias_runner) = alias_def.and_then(|alias| alias.runner.as_deref()) {
            runner_name = resolve_runner_name(Some(alias_runner), config);
        }
    }
    let info = registry
        .get(&runner_name)
        .or_else(|| registry.get(&config.default_runner))
        .or_else(|| registry.get("opencode"))?;
    Some((runner_name, info, alias_def))
}

fn supported_output_modes(runner_name: &str) -> &'static [&'static str] {
    match runner_name {
        "cc" | "claude" => &[
            "text",
            "stream-text",
            "json",
            "stream-json",
            "formatted",
            "stream-formatted",
        ],
        "k" | "kimi" => &[
            "text",
            "stream-text",
            "stream-json",
            "formatted",
            "stream-formatted",
        ],
        "oc" | "opencode" => &[
            "text",
            "stream-text",
            "json",
            "stream-json",
            "formatted",
            "stream-formatted",
        ],
        "cu" | "cursor" => &[
            "text",
            "stream-text",
            "json",
            "stream-json",
            "formatted",
            "stream-formatted",
        ],
        _ => &["text", "stream-text"],
    }
}

fn fallback_output_mode(supported: &[&str]) -> &'static str {
    if supported.iter().any(|mode| *mode == "text") {
        "text"
    } else {
        "stream-text"
    }
}

pub fn resolve_output_mode(
    parsed: &ParsedArgs,
    config: Option<&CccConfig>,
) -> Result<String, &'static str> {
    resolve_output_mode_with_source(parsed, config).map(|(mode, _)| mode)
}

fn resolve_output_mode_with_source(
    parsed: &ParsedArgs,
    config: Option<&CccConfig>,
) -> Result<(String, &'static str), &'static str> {
    let config = config.cloned().unwrap_or_default();
    let alias_def = resolve_alias_def(parsed, &config);
    let mut mode = parsed.output_mode.clone();
    let mut source = "argument";
    if mode.is_none() {
        mode = alias_def.and_then(|alias| alias.output_mode.clone());
        if mode.is_some() {
            source = "alias";
        }
    }
    let mode = mode.unwrap_or_else(|| {
        source = "configured";
        config.default_output_mode.clone()
    });
    if mode.is_empty() {
        return Err(
            "output mode requires one of: text, stream-text, json, stream-json, formatted, stream-formatted",
        );
    }
    match parse_output_mode(&mode) {
        Some(mode) => Ok((mode, source)),
        None => Err(
            "output mode must be one of: text, stream-text, json, stream-json, formatted, stream-formatted",
        ),
    }
}

pub fn resolve_show_thinking(parsed: &ParsedArgs, config: Option<&CccConfig>) -> bool {
    let config = config.cloned().unwrap_or_default();
    parsed
        .show_thinking
        .or_else(|| resolve_alias_def(parsed, &config).and_then(|alias| alias.show_thinking))
        .unwrap_or(config.default_show_thinking)
}

pub fn resolve_sanitize_osc(parsed: &ParsedArgs, config: Option<&CccConfig>) -> bool {
    let config = config.cloned().unwrap_or_default();
    parsed
        .sanitize_osc
        .or_else(|| resolve_alias_def(parsed, &config).and_then(|alias| alias.sanitize_osc))
        .or(config.default_sanitize_osc)
        .unwrap_or_else(|| {
            resolve_output_plan(parsed, Some(&config))
                .map(|plan| plan.mode.contains("formatted"))
                .unwrap_or(false)
        })
}

pub fn resolve_output_plan(
    parsed: &ParsedArgs,
    config: Option<&CccConfig>,
) -> Result<OutputPlan, &'static str> {
    let config = config.cloned().unwrap_or_default();
    let registry = RUNNER_REGISTRY.read().unwrap();
    let (runner_name, info, _) =
        resolve_effective_runner(parsed, &config, &registry).ok_or("no runner found")?;
    let (mut mode, mode_source) = resolve_output_mode_with_source(parsed, Some(&config))?;
    let supported = supported_output_modes(&runner_name);
    let mut warnings = Vec::new();
    if !supported.iter().any(|candidate| *candidate == mode) {
        if mode_source == "argument" {
            return Err("runner does not support requested output mode");
        }
        let fallback = fallback_output_mode(supported);
        warnings.push(format!(
            "warning: runner \"{}\" does not support {} output mode \"{}\"; falling back to \"{}\"",
            canonical_runner_name(&runner_name, info),
            mode_source,
            mode,
            fallback,
        ));
        mode = fallback.to_string();
    }

    if matches!(mode.as_str(), "text" | "stream-text") {
        return Ok(OutputPlan {
            runner_name,
            mode: mode.clone(),
            stream: mode.starts_with("stream-"),
            formatted: false,
            schema: None,
            argv_flags: Vec::new(),
            warnings,
        });
    }

    if matches!(runner_name.as_str(), "cc" | "claude") {
        let mut argv_flags = if mode == "json" {
            vec!["--output-format".into(), "json".into()]
        } else {
            vec![
                "--verbose".into(),
                "--output-format".into(),
                "stream-json".into(),
            ]
        };
        if mode == "stream-formatted" {
            argv_flags.push("--include-partial-messages".into());
        }
        return Ok(OutputPlan {
            runner_name,
            mode: mode.clone(),
            stream: mode.starts_with("stream-"),
            formatted: mode.contains("formatted"),
            schema: Some("claude-code".into()),
            argv_flags,
            warnings,
        });
    }

    if matches!(runner_name.as_str(), "k" | "kimi") {
        return Ok(OutputPlan {
            runner_name,
            mode: mode.clone(),
            stream: mode.starts_with("stream-"),
            formatted: mode.contains("formatted"),
            schema: Some("kimi".into()),
            argv_flags: vec![
                "--print".into(),
                "--output-format".into(),
                "stream-json".into(),
            ],
            warnings,
        });
    }

    if matches!(runner_name.as_str(), "oc" | "opencode") {
        return Ok(OutputPlan {
            runner_name,
            mode: mode.clone(),
            stream: mode.starts_with("stream-"),
            formatted: mode.contains("formatted"),
            schema: Some("opencode".into()),
            argv_flags: vec!["--format".into(), "json".into()],
            warnings,
        });
    }

    if matches!(runner_name.as_str(), "cu" | "cursor") {
        let argv_flags = if mode == "json" {
            vec!["--output-format".into(), "json".into()]
        } else {
            vec!["--output-format".into(), "stream-json".into()]
        };
        return Ok(OutputPlan {
            runner_name,
            mode: mode.clone(),
            stream: mode.starts_with("stream-"),
            formatted: mode.contains("formatted"),
            schema: Some("cursor-agent".into()),
            argv_flags,
            warnings,
        });
    }

    Ok(OutputPlan {
        runner_name,
        mode: mode.clone(),
        stream: mode.starts_with("stream-"),
        formatted: false,
        schema: None,
        argv_flags: Vec::new(),
        warnings,
    })
}

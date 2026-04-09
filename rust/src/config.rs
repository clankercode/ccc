use std::path::Path;

use crate::parser::CccConfig;

pub fn load_config(path: Option<&Path>) -> CccConfig {
    let mut config = CccConfig::default();

    let config_path = match path {
        Some(p) => Some(p.to_path_buf()),
        None => default_config_path(),
    };

    let config_path = match config_path {
        Some(p) if p.exists() => p,
        _ => return config,
    };

    let content = match std::fs::read_to_string(&config_path) {
        Ok(c) => c,
        Err(_) => return config,
    };

    parse_toml_config(&content, &mut config);
    config
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn default_config_path() -> Option<std::path::PathBuf> {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return Some(std::path::PathBuf::from(xdg).join("ccc/config.toml"));
        }
    }
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/ccc/config.toml"))
}

fn parse_toml_config(content: &str, config: &mut CccConfig) {
    let mut section: &str = "";
    let mut current_alias_name: Option<String> = None;
    let mut current_alias = crate::parser::AliasDef::default();

    let flush_alias = |config: &mut CccConfig,
                       current_alias_name: &mut Option<String>,
                       current_alias: &mut crate::parser::AliasDef| {
        if let Some(name) = current_alias_name.take() {
            config.aliases.insert(name, std::mem::take(current_alias));
        }
    };

    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }

        if trimmed.starts_with('[') {
            flush_alias(config, &mut current_alias_name, &mut current_alias);
            if trimmed == "[defaults]" {
                section = "defaults";
            } else if trimmed == "[abbreviations]" {
                section = "abbreviations";
            } else if let Some(name) = trimmed
                .strip_prefix("[aliases.")
                .and_then(|s| s.strip_suffix(']'))
            {
                section = "alias";
                current_alias_name = Some(name.to_string());
            } else if let Some(name) = trimmed
                .strip_prefix("[alias.")
                .and_then(|s| s.strip_suffix(']'))
            {
                section = "alias";
                current_alias_name = Some(name.to_string());
            } else {
                section = "";
            }
            continue;
        }

        if let Some((key, value)) = trimmed.split_once('=') {
            let key = key.trim();
            let value = value.trim().trim_matches('"');

            match (section, key) {
                ("defaults", "runner") => config.default_runner = value.to_string(),
                ("defaults", "provider") => config.default_provider = value.to_string(),
                ("defaults", "model") => config.default_model = value.to_string(),
                ("defaults", "thinking") => {
                    if let Ok(n) = value.parse::<i32>() {
                        config.default_thinking = Some(n);
                    }
                }
                ("defaults", "show_thinking") => {
                    if let Some(flag) = parse_bool(value) {
                        config.default_show_thinking = flag;
                    }
                }
                ("abbreviations", _) => {
                    config
                        .abbreviations
                        .insert(key.to_string(), value.to_string());
                }
                ("", "default_runner") => config.default_runner = value.to_string(),
                ("", "default_provider") => config.default_provider = value.to_string(),
                ("", "default_model") => config.default_model = value.to_string(),
                ("", "default_thinking") => {
                    if let Ok(n) = value.parse::<i32>() {
                        config.default_thinking = Some(n);
                    }
                }
                ("", "default_show_thinking") => {
                    if let Some(flag) = parse_bool(value) {
                        config.default_show_thinking = flag;
                    }
                }
                ("alias", "runner") => current_alias.runner = Some(value.to_string()),
                ("alias", "thinking") => {
                    if let Ok(n) = value.parse::<i32>() {
                        current_alias.thinking = Some(n);
                    }
                }
                ("alias", "show_thinking") => {
                    current_alias.show_thinking = parse_bool(value);
                }
                ("alias", "provider") => current_alias.provider = Some(value.to_string()),
                ("alias", "model") => current_alias.model = Some(value.to_string()),
                ("alias", "agent") => current_alias.agent = Some(value.to_string()),
                _ => {}
            }
        }
    }

    flush_alias(config, &mut current_alias_name, &mut current_alias);
}

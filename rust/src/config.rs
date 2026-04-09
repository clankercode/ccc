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

fn default_config_path() -> Option<std::path::PathBuf> {
    if let Ok(p) = std::env::var("CCC_CONFIG") {
        if !p.is_empty() {
            return Some(std::path::PathBuf::from(p));
        }
    }
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/ccc/config.toml"))
}

fn parse_toml_config(content: &str, config: &mut CccConfig) {
    let mut section: &str = "";

    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }

        if trimmed.starts_with('[') {
            if trimmed == "[defaults]" {
                section = "defaults";
            } else if trimmed == "[abbreviations]" {
                section = "abbreviations";
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
                ("", "default_runner") => config.default_runner = value.to_string(),
                ("", "default_provider") => config.default_provider = value.to_string(),
                ("", "default_model") => config.default_model = value.to_string(),
                ("", "default_thinking") => {
                    if let Ok(n) = value.parse::<i32>() {
                        config.default_thinking = Some(n);
                    }
                }
                _ => {}
            }
        }
    }
}

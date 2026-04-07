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
    let home = std::env::var("HOME").ok()?;
    Some(std::path::PathBuf::from(home).join(".config/ccc/config.toml"))
}

fn parse_toml_config(content: &str, config: &mut CccConfig) {
    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with('#') || trimmed.is_empty() || trimmed.starts_with('[') {
            continue;
        }

        if let Some((key, value)) = trimmed.split_once('=') {
            let key = key.trim();
            let value = value.trim().trim_matches('"');

            match key {
                "runner" => config.default_runner = value.to_string(),
                "provider" => config.default_provider = value.to_string(),
                "model" => config.default_model = value.to_string(),
                "thinking" => {
                    if let Ok(n) = value.parse::<i32>() {
                        config.default_thinking = Some(n);
                    }
                }
                _ => {}
            }
        }
    }
}

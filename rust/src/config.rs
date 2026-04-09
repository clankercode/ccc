use std::path::Path;
use std::path::PathBuf;

use crate::parser::CccConfig;

pub fn load_config(path: Option<&Path>) -> CccConfig {
    let mut config = CccConfig::default();

    let config_paths = match path {
        Some(p) => vec![p.to_path_buf()],
        None => {
            let current_dir = std::env::current_dir().ok();
            let home_path = std::env::var("HOME")
                .ok()
                .map(|home| PathBuf::from(home).join(".config/ccc/config.toml"));
            let xdg_path = std::env::var("XDG_CONFIG_HOME").ok().and_then(|xdg| {
                if xdg.is_empty() {
                    None
                } else {
                    Some(PathBuf::from(xdg).join("ccc/config.toml"))
                }
            });
            default_config_paths_from(
                current_dir.as_deref(),
                home_path.as_deref(),
                xdg_path.as_deref(),
            )
        }
    };

    for config_path in config_paths {
        if !config_path.exists() {
            continue;
        }
        let content = match std::fs::read_to_string(&config_path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        parse_toml_config(&content, &mut config);
    }

    config
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn default_config_paths_from(
    current_dir: Option<&Path>,
    home_path: Option<&Path>,
    xdg_path: Option<&Path>,
) -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(home) = home_path {
        paths.push(home.to_path_buf());
    }

    if let Some(xdg) = xdg_path {
        if Some(xdg) != home_path {
            paths.push(xdg.to_path_buf());
        }
    }

    if let Some(cwd) = current_dir {
        for directory in cwd.ancestors() {
            let candidate = directory.join(".ccc.toml");
            if candidate.exists() {
                paths.push(candidate);
                break;
            }
        }
    }

    paths
}

fn merge_alias(target: &mut crate::parser::AliasDef, overlay: &crate::parser::AliasDef) {
    if overlay.runner.is_some() {
        target.runner = overlay.runner.clone();
    }
    if overlay.thinking.is_some() {
        target.thinking = overlay.thinking;
    }
    if overlay.show_thinking.is_some() {
        target.show_thinking = overlay.show_thinking;
    }
    if overlay.sanitize_osc.is_some() {
        target.sanitize_osc = overlay.sanitize_osc;
    }
    if overlay.output_mode.is_some() {
        target.output_mode = overlay.output_mode.clone();
    }
    if overlay.provider.is_some() {
        target.provider = overlay.provider.clone();
    }
    if overlay.model.is_some() {
        target.model = overlay.model.clone();
    }
    if overlay.agent.is_some() {
        target.agent = overlay.agent.clone();
    }
    if overlay.prompt.is_some() {
        target.prompt = overlay.prompt.clone();
    }
}

fn parse_toml_config(content: &str, config: &mut CccConfig) {
    let mut section: &str = "";
    let mut current_alias_name: Option<String> = None;
    let mut current_alias = crate::parser::AliasDef::default();

    let flush_alias = |config: &mut CccConfig,
                       current_alias_name: &mut Option<String>,
                       current_alias: &mut crate::parser::AliasDef| {
        if let Some(name) = current_alias_name.take() {
            let overlay = std::mem::take(current_alias);
            config
                .aliases
                .entry(name)
                .and_modify(|existing| merge_alias(existing, &overlay))
                .or_insert(overlay);
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
                ("defaults", "output_mode") => config.default_output_mode = value.to_string(),
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
                ("defaults", "sanitize_osc") => {
                    config.default_sanitize_osc = parse_bool(value);
                }
                ("abbreviations", _) => {
                    config
                        .abbreviations
                        .insert(key.to_string(), value.to_string());
                }
                ("", "default_runner") => config.default_runner = value.to_string(),
                ("", "default_provider") => config.default_provider = value.to_string(),
                ("", "default_model") => config.default_model = value.to_string(),
                ("", "default_output_mode") => config.default_output_mode = value.to_string(),
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
                ("", "default_sanitize_osc") => {
                    config.default_sanitize_osc = parse_bool(value);
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
                ("alias", "sanitize_osc") => {
                    current_alias.sanitize_osc = parse_bool(value);
                }
                ("alias", "output_mode") => current_alias.output_mode = Some(value.to_string()),
                ("alias", "provider") => current_alias.provider = Some(value.to_string()),
                ("alias", "model") => current_alias.model = Some(value.to_string()),
                ("alias", "agent") => current_alias.agent = Some(value.to_string()),
                ("alias", "prompt") => current_alias.prompt = Some(value.to_string()),
                _ => {}
            }
        }
    }

    flush_alias(config, &mut current_alias_name, &mut current_alias);
}

#[cfg(test)]
mod tests {
    use super::{default_config_paths_from, parse_toml_config};
    use crate::parser::CccConfig;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn test_load_config_prefers_nearest_project_local_file() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let base_dir = std::env::temp_dir().join(format!("ccc-rust-project-config-{unique}"));
        let workspace_dir = base_dir.join("workspace");
        let repo_dir = workspace_dir.join("repo");
        let nested_dir = repo_dir.join("nested").join("deeper");
        let home_config_dir = base_dir.join("home").join(".config").join("ccc");
        let xdg_config_dir = base_dir.join("xdg").join("ccc");
        let workspace_config = workspace_dir.join(".ccc.toml");
        let repo_config = repo_dir.join(".ccc.toml");
        let home_config = home_config_dir.join("config.toml");
        let xdg_config = xdg_config_dir.join("config.toml");

        fs::create_dir_all(&nested_dir).unwrap();
        fs::create_dir_all(&home_config_dir).unwrap();
        fs::create_dir_all(&xdg_config_dir).unwrap();
        fs::write(
            &workspace_config,
            r#"
[defaults]
runner = "oc"

[aliases.review]
agent = "outer-agent"
"#,
        )
        .unwrap();
        fs::write(
            &repo_config,
            r#"
[aliases.review]
prompt = "Repo prompt"
"#,
        )
        .unwrap();
        fs::write(
            &home_config,
            r#"
[defaults]
runner = "k"

[aliases.review]
show_thinking = true
"#,
        )
        .unwrap();
        fs::write(
            &xdg_config,
            r#"
[defaults]
model = "xdg-model"

[aliases.review]
model = "xdg-model"
"#,
        )
        .unwrap();

        let paths = default_config_paths_from(
            Some(&nested_dir),
            Some(&home_config),
            Some(&xdg_config),
        );
        assert_eq!(paths, vec![home_config.clone(), xdg_config.clone(), repo_config.clone()]);
        assert!(!paths.contains(&workspace_config));

        let mut config = CccConfig::default();
        for path in &paths {
            let content = fs::read_to_string(path).unwrap();
            parse_toml_config(&content, &mut config);
        }

        assert_eq!(config.default_runner, "k");
        assert_eq!(config.default_model, "xdg-model");
        let review = config.aliases.get("review").unwrap();
        assert_eq!(review.prompt.as_deref(), Some("Repo prompt"));
        assert_eq!(review.model.as_deref(), Some("xdg-model"));
        assert_eq!(review.show_thinking, Some(true));
        assert_eq!(review.agent.as_deref(), None);
    }
}

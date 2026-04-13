use crate::RUNNER_REGISTRY;
use serde_json::Value;
use std::fs;
use std::path::Path;
#[cfg(test)]
use std::path::PathBuf;
use std::process::{Command, Stdio};

struct RunnerStatus {
    name: String,
    #[allow(dead_code)]
    alias: String,
    binary: String,
    found: bool,
    version: String,
}

const CANONICAL_RUNNERS: &[(&str, &str)] = &[
    ("opencode", "oc"),
    ("claude", "cc"),
    ("kimi", "k"),
    ("codex", "c/cx"),
    ("roocode", "rc"),
    ("crush", "cr"),
    ("cursor", "cu"),
];

const HELP_TEXT: &str = r#"ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc config
  ccc add [-g] <alias>
  ccc --print-config
  ccc --help
  ccc -h
  ccc @reviewer --help

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr), cursor (cu)
  +thinking     Set thinking level: +0..+4 or +none/+low/+med/+mid/+medium/+high/+max/+xhigh
                Claude maps +0 to --thinking disabled and +1..+4 to --thinking enabled with matching --effort
                Kimi maps +0 to --no-thinking and +1..+4 to --thinking
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, runner names select runners before agent fallback
                Presets can also define a default prompt when the user leaves prompt text blank
                prompt_mode lets alias prompts prepend or append text; prepend/append require an explicit prompt argument
  .mode / ..mode
                Output-mode sugar with a shared dot identity:
                  .text / ..text, .json / ..json, .fmt / ..fmt
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported
  --save-session
                Allow the selected runner to save this run in its normal session history
  --cleanup-session
                Try to clean up the created session after the run when no no-persist flag exists

Flags:
  --print-config                         Print the canonical example config.toml and exit
  --help / -h                           Print help and exit, even when mixed with other args
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: on; config key: show_thinking)
  --sanitize-osc / --no-sanitize-osc    Strip disruptive OSC control output in human-facing modes
                                        while preserving OSC 8 hyperlinks
                                        (config key: defaults.sanitize_osc)
  --output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted>
                                        Select raw, streamed, or formatted output handling
                                        (config key: defaults.output_mode)
  --forward-unknown-json                In formatted modes, forward unhandled JSON objects to stderr
  Environment:
    FORCE_COLOR / NO_COLOR              Override TTY detection for formatted human output
                                        (FORCE_COLOR wins if both are set)
  --            Treat all remaining args as prompt text, even if they look like controls

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc --permission-mode auto c "Add tests"
  ccc --yolo cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc --permission-mode plan k "Think before editing"
  ccc ..fmt cc +3 "Investigate the failing test"
  ccc -o stream-json k "Reply with exactly pong"
  ccc @reviewer k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"
  ccc -y -- +1 @agent :model
  ccc --print-config

Config:
  ccc config                            — print every resolved config file path and contents
  ccc add [-g] <alias>                  — prompt for alias settings and write them to config
  ccc add <alias> --runner cc --prompt "Review" --yes
                                        — write an alias non-interactively
  ccc --print-config                    — print the canonical example config.toml
  .ccc.toml (searched upward from CWD)  — project-local presets and defaults
  XDG_CONFIG_HOME/ccc/config.toml       — global defaults when XDG is set
  ~/.config/ccc/config.toml             — legacy global fallback
"#;

fn get_version(binary: &str) -> String {
    match Command::new(binary)
        .arg("--version")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .lines()
            .next()
            .unwrap_or("")
            .to_string(),
        _ => String::new(),
    }
}

fn read_json_version(package_json_path: &Path, expected_name: &str) -> String {
    let payload = match fs::read_to_string(package_json_path) {
        Ok(text) => text,
        Err(_) => return String::new(),
    };
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return String::new(),
    };
    if parsed.get("name").and_then(Value::as_str) != Some(expected_name) {
        return String::new();
    }
    parsed
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn discover_opencode_version(binary_path: &Path) -> String {
    read_json_version(
        &binary_path
            .parent()
            .unwrap_or(binary_path)
            .parent()
            .unwrap_or(binary_path)
            .join("package.json"),
        "opencode-ai",
    )
}

fn discover_codex_version(binary_path: &Path) -> String {
    let version = read_json_version(
        &binary_path
            .parent()
            .unwrap_or(binary_path)
            .parent()
            .unwrap_or(binary_path)
            .join("package.json"),
        "@openai/codex",
    );
    if version.is_empty() {
        String::new()
    } else {
        format!("codex-cli {version}")
    }
}

fn discover_claude_version(binary_path: &Path) -> String {
    let parts: Vec<_> = binary_path
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    if parts.len() < 3 || parts[parts.len() - 3] != "claude" || parts[parts.len() - 2] != "versions"
    {
        return String::new();
    }
    let version = &parts[parts.len() - 1];
    if version.is_empty() {
        String::new()
    } else {
        format!("{version} (Claude Code)")
    }
}

fn discover_kimi_version(binary_path: &Path) -> String {
    if binary_path
        .parent()
        .and_then(Path::file_name)
        .and_then(|value| value.to_str())
        != Some("bin")
    {
        return String::new();
    }
    let lib_dir = match binary_path.parent().and_then(Path::parent) {
        Some(parent) => parent.join("lib"),
        None => return String::new(),
    };
    let lib_entries = match fs::read_dir(&lib_dir) {
        Ok(entries) => entries,
        Err(_) => return String::new(),
    };
    for lib_entry in lib_entries.flatten() {
        let python_dir = lib_entry.path();
        let site_packages = python_dir.join("site-packages");
        let dist_entries = match fs::read_dir(&site_packages) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for dist_entry in dist_entries.flatten() {
            let dist_path = dist_entry.path();
            let Some(name) = dist_path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            if !name.starts_with("kimi_cli-") || !name.ends_with(".dist-info") {
                continue;
            }
            let metadata_path = dist_path.join("METADATA");
            let Ok(metadata) = fs::read_to_string(metadata_path) else {
                continue;
            };
            for line in metadata.lines() {
                if let Some(version) = line.strip_prefix("Version: ") {
                    if !version.trim().is_empty() {
                        return format!("kimi, version {}", version.trim());
                    }
                    return String::new();
                }
            }
        }
    }
    String::new()
}

fn json_name_matches(package_json_path: &Path, expected_name: &str) -> bool {
    let payload = match fs::read_to_string(package_json_path) {
        Ok(text) => text,
        Err(_) => return false,
    };
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return false,
    };
    parsed.get("name").and_then(Value::as_str) == Some(expected_name)
}

fn read_cursor_release_version(index_path: &Path) -> String {
    let text = match fs::read_to_string(index_path) {
        Ok(text) => text,
        Err(_) => return String::new(),
    };
    let marker = "agent-cli@";
    let Some(start) = text.find(marker) else {
        return String::new();
    };
    text[start + marker.len()..]
        .chars()
        .take_while(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
        .collect()
}

fn discover_cursor_version(binary_path: &Path) -> String {
    let package_root = binary_path.parent().unwrap_or(binary_path);
    if !json_name_matches(
        &package_root.join("package.json"),
        "@anysphere/agent-cli-runtime",
    ) {
        return String::new();
    }
    read_cursor_release_version(&package_root.join("index.js"))
}

fn get_runner_version(runner_name: &str, binary: &str, binary_path: &Path) -> String {
    let real_path = match fs::canonicalize(binary_path) {
        Ok(path) => path,
        Err(_) => binary_path.to_path_buf(),
    };
    let version = match runner_name {
        "opencode" => discover_opencode_version(&real_path),
        "codex" => discover_codex_version(&real_path),
        "claude" => discover_claude_version(&real_path),
        "kimi" => discover_kimi_version(&real_path),
        "cursor" => discover_cursor_version(&real_path),
        _ => String::new(),
    };
    if version.is_empty() {
        get_version(binary)
    } else {
        version
    }
}

fn is_on_path(binary: &str) -> bool {
    resolve_binary_path(binary).is_some()
}

fn resolve_binary_path(binary: &str) -> Option<String> {
    Command::new("which")
        .arg(binary)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
        .and_then(|output| {
            if output.status.success() {
                String::from_utf8(output.stdout).ok()
            } else {
                None
            }
        })
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn runner_checklist() -> Vec<RunnerStatus> {
    let mut statuses = Vec::new();
    for &(name, alias) in CANONICAL_RUNNERS {
        let registry = RUNNER_REGISTRY.read().unwrap();
        let binary = registry
            .get(name)
            .map(|info| info.binary.clone())
            .unwrap_or_else(|| name.to_string());
        drop(registry);

        let found = is_on_path(&binary);
        let version = if found {
            let binary_path = resolve_binary_path(&binary);
            match binary_path {
                Some(path) => get_runner_version(name, &binary, Path::new(&path)),
                None => get_version(&binary),
            }
        } else {
            String::new()
        };
        statuses.push(RunnerStatus {
            name: name.to_string(),
            alias: alias.to_string(),
            binary,
            found,
            version,
        });
    }
    statuses
}

fn format_runner_checklist() -> String {
    let mut out = String::from("Runners:\n");
    for s in runner_checklist() {
        if s.found {
            let tag = if s.version.is_empty() {
                "found"
            } else {
                &s.version
            };
            out.push_str(&format!("  [+] {:10} ({})  {}\n", s.name, s.binary, tag));
        } else {
            out.push_str(&format!("  [-] {:10} ({})  not found\n", s.name, s.binary));
        }
    }
    out
}

pub fn print_help() {
    print!("{}", HELP_TEXT);
    print!("{}", format_runner_checklist());
}

pub fn print_usage() {
    eprintln!("usage: ccc [controls...] \"<Prompt>\"");
    eprint!("{}", format_runner_checklist());
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("ccc-help-{label}-{unique}"));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn test_get_runner_version_reads_opencode_package_json_before_command() {
        let root = unique_temp_dir("opencode");
        let package_root = root.join("node_modules").join("opencode-ai");
        let binary_path = package_root.join("bin").join("opencode");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"opencode-ai","version":"1.2.3"}"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/bin/sh\nexit 99\n").unwrap();

        assert_eq!(
            get_runner_version("opencode", "definitely-missing-binary", &binary_path),
            "1.2.3"
        );
    }

    #[test]
    fn test_get_runner_version_reads_codex_package_json_before_command() {
        let root = unique_temp_dir("codex");
        let package_root = root.join("node_modules").join("@openai").join("codex");
        let binary_path = package_root.join("bin").join("codex.js");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"@openai/codex","version":"0.118.0"}"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/usr/bin/env node\n").unwrap();

        assert_eq!(
            get_runner_version("codex", "definitely-missing-binary", &binary_path),
            "codex-cli 0.118.0"
        );
    }

    #[test]
    fn test_get_runner_version_reads_claude_version_from_install_path() {
        let root = unique_temp_dir("claude");
        let versions_dir = root.join("claude").join("versions");
        fs::create_dir_all(&versions_dir).unwrap();
        let binary_path = versions_dir.join("2.1.98");
        fs::write(&binary_path, "").unwrap();

        assert_eq!(
            get_runner_version("claude", "definitely-missing-binary", &binary_path),
            "2.1.98 (Claude Code)"
        );
    }

    #[test]
    fn test_get_runner_version_reads_kimi_metadata_before_command() {
        let root = unique_temp_dir("kimi");
        let binary_path = root.join("bin").join("kimi");
        let metadata_dir = root
            .join("lib")
            .join("python3.13")
            .join("site-packages")
            .join("kimi_cli-1.30.0.dist-info");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::create_dir_all(&metadata_dir).unwrap();
        fs::write(&binary_path, "#!/usr/bin/env python3\n").unwrap();
        fs::write(
            metadata_dir.join("METADATA"),
            "Metadata-Version: 2.3\nName: kimi-cli\nVersion: 1.30.0\n",
        )
        .unwrap();

        assert_eq!(
            get_runner_version("kimi", "definitely-missing-binary", &binary_path),
            "kimi, version 1.30.0"
        );
    }

    #[test]
    fn test_get_runner_version_reads_cursor_release_marker_before_command() {
        let root = unique_temp_dir("cursor");
        let package_root = root.join("cursor-agent");
        let binary_path = package_root.join("cursor-agent");
        fs::create_dir_all(&package_root).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"@anysphere/agent-cli-runtime","private":true}"#,
        )
        .unwrap();
        fs::write(
            package_root.join("index.js"),
            r#"globalThis.SENTRY_RELEASE={id:"agent-cli@2026.03.30-a5d3e17"};"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/bin/sh\nexit 99\n").unwrap();

        assert_eq!(
            get_runner_version("cursor", "definitely-missing-binary", &binary_path),
            "2026.03.30-a5d3e17"
        );
    }

    #[test]
    fn test_get_runner_version_falls_back_when_metadata_is_missing() {
        assert_eq!(
            get_runner_version(
                "opencode",
                "definitely-missing-binary",
                Path::new("/tmp/missing/opencode")
            ),
            ""
        );
    }
}

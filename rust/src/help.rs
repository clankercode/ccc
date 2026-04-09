use crate::RUNNER_REGISTRY;
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
];

const HELP_TEXT: &str = r#"ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
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

fn is_on_path(binary: &str) -> bool {
    Command::new("which")
        .arg(binary)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
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
            get_version(&binary)
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
    eprintln!("usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"");
    eprint!("{}", format_runner_checklist());
}

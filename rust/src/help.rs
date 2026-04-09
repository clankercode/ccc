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
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc --print-config
  ccc --help
  ccc -h

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0..+4 or +none/+low/+med/+mid/+medium/+high/+max/+xhigh
                Claude maps +0 to --thinking disabled and +1..+4 to --thinking enabled with matching --effort
                Kimi maps +0 to --no-thinking and +1..+4 to --thinking
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent
                Presets can also define a default prompt when the user leaves prompt text blank
  .mode / ..mode
                Output-mode sugar with a shared dot identity:
                  .text / ..text, .json / ..json, .fmt / ..fmt
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported

Flags:
  --print-config                         Print the canonical example config.toml and exit
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: off; config key: show_thinking)
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
    eprintln!(
        "usage: ccc [controls...] \"<Prompt>\""
    );
    eprint!("{}", format_runner_checklist());
}

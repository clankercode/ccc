use std::fs;
use std::io::Write;
use std::process::Command;
use std::process::Stdio;
use std::time::{SystemTime, UNIX_EPOCH};

fn ccc_bin() -> &'static str {
    env!("CARGO_BIN_EXE_ccc")
}

fn example_config_fixture() -> String {
    std::fs::read_to_string(format!(
        "{}/../tests/fixtures/config-example.toml",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}

#[test]
fn test_help_mentions_name_slot() {
    let output = Command::new(ccc_bin()).arg("--help").output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Usage:\n  ccc [controls...] \"<Prompt>\""));
    assert!(stdout.contains(
        "@name         Use a named preset from config; if no preset exists, treat it as an agent"
    ));
    assert!(stdout.contains(
        "Presets can also define a default prompt when the user leaves prompt text blank"
    ));
    assert!(stdout.contains("ccc config"));
    assert!(stdout.contains("--print-config"));
    assert!(stdout.contains("--help / -h"));
    assert!(stdout.contains(
        "--show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it"
    ));
    assert!(stdout.contains("--sanitize-osc / --no-sanitize-osc"));
    assert!(stdout.contains(
        "--output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted>"
    ));
    assert!(stdout.contains("--forward-unknown-json"));
    assert!(stdout.contains(".text / ..text, .json / ..json, .fmt / ..fmt"));
    assert!(stdout.contains("--permission-mode <safe|auto|yolo|plan>"));
    assert!(stdout.contains("--yolo / -y"));
    assert!(stdout.contains("--save-session"));
    assert!(stdout.contains("--cleanup-session"));
    assert!(stdout.contains("Treat all remaining args as prompt text"));
    assert!(stdout.contains(".ccc.toml (searched upward from CWD)"));
    assert!(stdout.contains("XDG_CONFIG_HOME/ccc/config.toml"));
    assert!(stdout.contains("~/.config/ccc/config.toml"));
    assert!(stdout.contains("show_thinking"));
    assert!(stdout
        .contains("opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)"));
}

#[test]
fn test_usage_mentions_name_slot() {
    let output = Command::new(ccc_bin()).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("usage: ccc [controls...] \"<Prompt>\""));
}

#[test]
fn test_print_config_outputs_example_config() {
    let output = Command::new(ccc_bin())
        .arg("--print-config")
        .output()
        .unwrap();
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        example_config_fixture()
    );
    assert!(output.stderr.is_empty());
}

#[test]
fn test_print_config_rejects_mixed_usage() {
    let output = Command::new(ccc_bin())
        .args(["--print-config", "cc"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("--print-config"));
}

#[test]
fn test_help_wins_when_mixed_with_other_args() {
    let output = Command::new(ccc_bin())
        .args(["@reviewer", "--help"])
        .output()
        .unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Usage:\n  ccc [controls...] \"<Prompt>\""));
    assert!(stdout.contains("--help / -h"));
}

#[test]
fn test_add_alias_yes_writes_config() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-add-alias-{unique}"));
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let config_path = xdg_root.join("ccc/config.toml");

    let output = Command::new(ccc_bin())
        .args([
            "add",
            "mm27",
            "--runner",
            "cc",
            "--model",
            "claude-4",
            "--prompt",
            "Review changes",
            "--prompt-mode",
            "default",
            "--yes",
        ])
        .env("HOME", &home_root)
        .env("XDG_CONFIG_HOME", &xdg_root)
        .env("CCC_CONFIG", base_dir.join("missing.toml"))
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        "[aliases.mm27]\n\
runner = \"cc\"\n\
model = \"claude-4\"\n\
prompt = \"Review changes\"\n\
prompt_mode = \"default\"\n"
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(&format!("Config path: {}", config_path.display())));
    assert!(stdout.contains("\n✓  Alias @mm27 written\n\n"));
    assert!(stdout.contains("  [aliases.mm27]\n"));
    assert!(output.stderr.is_empty());
}

#[test]
fn test_add_alias_cancel_existing_leaves_file_unchanged() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-add-alias-cancel-{unique}"));
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let config_path = xdg_root.join("ccc/config.toml");
    fs::create_dir_all(config_path.parent().unwrap()).unwrap();
    let original = "[aliases.mm27]\nprompt = \"old\"\n";
    fs::write(&config_path, original).unwrap();

    let mut child = Command::new(ccc_bin())
        .args(["add", "mm27"])
        .env("HOME", &home_root)
        .env("XDG_CONFIG_HOME", &xdg_root)
        .env("CCC_CONFIG", base_dir.join("missing.toml"))
        .env("FORCE_COLOR", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.as_mut().unwrap().write_all(b"3\n").unwrap();
    let output = child.wait_with_output().unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(fs::read_to_string(&config_path).unwrap(), original);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Existing alias action"));
    assert!(stdout.contains("(1-3)"));
    assert!(stdout.contains("  [m]odify, [r]eplace, [c]ancel"));
    assert!(stdout.contains("default"));
    assert!(stdout.contains("choice >"));
    assert!(stdout.contains("\x1b["));
    assert!(stdout.contains("Cancelled"));
}

#[test]
fn test_add_alias_existing_replace_accepts_numbered_choices() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-add-alias-replace-{unique}"));
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let config_path = xdg_root.join("ccc/config.toml");
    fs::create_dir_all(config_path.parent().unwrap()).unwrap();
    fs::write(&config_path, "[aliases.mm27]\nprompt = \"old\"\n").unwrap();

    let mut child = Command::new(ccc_bin())
        .args(["add", "mm27"])
        .env("HOME", &home_root)
        .env("XDG_CONFIG_HOME", &xdg_root)
        .env("CCC_CONFIG", base_dir.join("missing.toml"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"2\noc\n\n\n3\n3\n1\n2\n\nFix the failing tests\n2\n1\n")
        .unwrap();
    let output = child.wait_with_output().unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        "[aliases.mm27]\n\
runner = \"oc\"\n\
thinking = 1\n\
show_thinking = false\n\
output_mode = \"text\"\n\
prompt = \"Fix the failing tests\"\n\
prompt_mode = \"default\"\n"
    );
}

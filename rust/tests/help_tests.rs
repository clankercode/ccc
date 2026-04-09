use std::process::Command;

fn ccc_bin() -> &'static str {
    env!("CARGO_BIN_EXE_ccc")
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

use std::process::Command;

fn ccc_bin() -> &'static str {
    env!("CARGO_BIN_EXE_ccc")
}

#[test]
fn test_help_mentions_name_slot() {
    let output = Command::new(ccc_bin()).arg("--help").output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(
        "Usage:\n  ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""
    ));
    assert!(stdout.contains(
        "@name         Use a named preset from config; if no preset exists, treat it as an agent"
    ));
}

#[test]
fn test_usage_mentions_name_slot() {
    let output = Command::new(ccc_bin()).output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains(
        "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""
    ));
}

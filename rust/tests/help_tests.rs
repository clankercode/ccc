use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
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

fn version_fixture() -> String {
    std::fs::read_to_string(format!("{}/../VERSION", env!("CARGO_MANIFEST_DIR")))
        .unwrap()
        .trim()
        .to_string()
}

#[test]
fn test_help_mentions_name_slot() {
    let output = Command::new(ccc_bin()).arg("--help").output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Usage:\n  ccc [controls...] \"<Prompt>\""));
    assert!(stdout.contains(
        "@name         Use a named preset from config; if no preset exists, runner names select runners before agent fallback"
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
        "--output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted|pass-text|pt|stream-pass-text|stream-pt|pass-json|pj|stream-pass-json|stream-pj>"
    ));
    assert!(stdout.contains("--forward-unknown-json"));
    assert!(stdout.contains(".text / ..text, .json / ..json, .fmt / ..fmt, .pt / ..pt, .pj / ..pj"));
    assert!(stdout.contains("--permission-mode <safe|auto|yolo|plan>"));
    assert!(stdout.contains("--yolo / -y"));
    assert!(stdout.contains("--version / -v"));
    assert!(stdout.contains("--save-session"));
    assert!(stdout.contains("--cleanup-session"));
    assert!(stdout.contains("Treat all remaining args as prompt text"));
    assert!(stdout.contains(".ccc.toml (searched upward from CWD)"));
    assert!(stdout.contains("XDG_CONFIG_HOME/ccc/config.toml"));
    assert!(stdout.contains("~/.config/ccc/config.toml"));
    assert!(stdout.contains("show_thinking"));
    assert!(stdout.contains(
        "opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr), cursor (cu), gemini (g)"
    ));
}

#[test]
fn test_version_prints_build_version_and_resolved_clients() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-version-{unique}"));
    let bin_dir = base_dir.join("bin");
    let package_root = base_dir.join("node_modules").join("opencode-ai");
    let package_bin = package_root.join("bin");
    fs::create_dir_all(&package_bin).unwrap();
    fs::create_dir_all(&bin_dir).unwrap();
    fs::write(
        package_root.join("package.json"),
        r#"{"name":"opencode-ai","version":"1.3.17"}"#,
    )
    .unwrap();
    fs::write(&package_bin.join("opencode"), "#!/bin/sh\nexit 99\n").unwrap();
    fs::write(
        bin_dir.join("which"),
        format!(
            "#!/bin/sh\nif [ \"$1\" = \"opencode\" ]; then\n  printf '%s\\n' '{}'\n  exit 0\nfi\nexit 1\n",
            package_bin.join("opencode").display()
        ),
    )
    .unwrap();
    fs::set_permissions(bin_dir.join("which"), fs::Permissions::from_mode(0o755)).unwrap();

    for flag in ["--version", "-v"] {
        let output = Command::new(ccc_bin())
            .arg(flag)
            .env("PATH", bin_dir.display().to_string())
            .output()
            .unwrap();

        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(output.stderr.is_empty());
        let stdout = String::from_utf8_lossy(&output.stdout);
        let lines: Vec<_> = stdout.trim().lines().collect();
        assert!(lines.len() >= 3, "{stdout}");
        assert_eq!(lines[0], format!("ccc version {}", version_fixture()));
        assert_eq!(lines[1], "Resolved clients:");
        assert!(stdout.contains("[+] opencode"));
        assert!(stdout.contains("1.3.17"));
        assert!(stdout.contains("(and 7 unresolved)"));
    }
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

#[test]
fn test_text_mode_with_show_thinking_surfaces_opencode_tool_work() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-text-visible-work-{unique}"));
    let config_path = base_dir.join("ccc-config.toml");
    fs::create_dir_all(&base_dir).unwrap();
    fs::write(&config_path, "").unwrap();

    let output = Command::new(ccc_bin())
        .args(["oc", "--show-thinking", "tool call"])
        .env(
            "CCC_REAL_OPENCODE",
            format!(
                "{}/../tests/mock-coding-cli/mock_coding_cli.sh",
                env!("CARGO_MANIFEST_DIR")
            ),
        )
        .env("MOCK_JSON_SCHEMA", "opencode")
        .env("CCC_CONFIG", &config_path)
        .env("HOME", base_dir.join("home"))
        .env("XDG_CONFIG_HOME", base_dir.join("xdg"))
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stdout.contains("read"));
    assert!(stdout.contains("read (ok)"));
    assert!(stdout.contains("mock: tool call executed"));
    assert!(stderr.contains("warning: runner \"opencode\" may save this session"));
}

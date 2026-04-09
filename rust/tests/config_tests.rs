use call_coding_clis::load_config;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn test_load_config_parses_alias_agent() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-{unique}"));
    let config_path = base_dir.join("config.toml");
    fs::create_dir_all(&base_dir).unwrap();
    fs::write(
        &config_path,
        r#"
[defaults]
runner = "cc"
provider = "anthropic"
model = "claude-4"
output_mode = "stream-formatted"
thinking = 2
show_thinking = true
sanitize_osc = false

[abbreviations]
mycc = "cc"

[aliases.work]
runner = "cc"
thinking = 3
show_thinking = true
sanitize_osc = false
output_mode = "formatted"
model = "claude-4"
agent = "reviewer"

[aliases.quick]
runner = "oc"

[aliases.commit]
prompt = "Commit all changes"
"#,
    )
    .unwrap();

    let config = load_config(Some(&config_path));

    assert_eq!(config.default_runner, "cc");
    assert_eq!(config.default_provider, "anthropic");
    assert_eq!(config.default_model, "claude-4");
    assert_eq!(config.default_output_mode, "stream-formatted");
    assert_eq!(config.default_thinking, Some(2));
    assert!(config.default_show_thinking);
    assert_eq!(config.default_sanitize_osc, Some(false));
    assert_eq!(
        config.abbreviations.get("mycc").map(|s| s.as_str()),
        Some("cc")
    );
    let work = config.aliases.get("work").unwrap();
    assert_eq!(work.runner.as_deref(), Some("cc"));
    assert_eq!(work.thinking, Some(3));
    assert_eq!(work.show_thinking, Some(true));
    assert_eq!(work.sanitize_osc, Some(false));
    assert_eq!(work.output_mode.as_deref(), Some("formatted"));
    assert_eq!(work.model.as_deref(), Some("claude-4"));
    assert_eq!(work.agent.as_deref(), Some("reviewer"));
    let quick = config.aliases.get("quick").unwrap();
    assert_eq!(quick.runner.as_deref(), Some("oc"));
    let commit = config.aliases.get("commit").unwrap();
    assert_eq!(commit.prompt.as_deref(), Some("Commit all changes"));
}

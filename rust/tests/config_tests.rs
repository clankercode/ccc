use call_coding_clis::{
    find_alias_write_path, find_config_command_path, load_config, render_alias_block,
    render_example_config, upsert_alias_block, AliasDef,
};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn example_config_fixture() -> String {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures/config-example.toml");
    fs::read_to_string(path).unwrap()
}

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
prompt_mode = "append"
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
    assert_eq!(commit.prompt_mode.as_deref(), Some("append"));
}

#[test]
fn test_render_example_config_matches_fixture() {
    assert_eq!(render_example_config(), example_config_fixture());
}

#[test]
fn test_legacy_default_keys_are_ignored() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-legacy-{unique}"));
    let config_path = base_dir.join("config.toml");
    fs::create_dir_all(&base_dir).unwrap();
    fs::write(
        &config_path,
        r#"
default_runner = "cc"
default_provider = "anthropic"
default_model = "claude-4"
default_output_mode = "json"
default_thinking = 4
default_show_thinking = true
default_sanitize_osc = false
"#,
    )
    .unwrap();

    let config = load_config(Some(&config_path));

    assert_eq!(config.default_runner, "oc");
    assert_eq!(config.default_provider, "");
    assert_eq!(config.default_model, "");
    assert_eq!(config.default_output_mode, "text");
    assert_eq!(config.default_thinking, None);
    assert!(!config.default_show_thinking);
    assert_eq!(config.default_sanitize_osc, None);
}

#[test]
fn test_singular_alias_section_is_ignored() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-singular-alias-{unique}"));
    let config_path = base_dir.join("config.toml");
    fs::create_dir_all(&base_dir).unwrap();
    fs::write(
        &config_path,
        r#"
[alias.work]
runner = "cc"
"#,
    )
    .unwrap();

    let config = load_config(Some(&config_path));

    assert!(config.aliases.is_empty());
}

#[test]
fn test_find_config_command_path_prefers_explicit_ccc_config() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-command-explicit-{unique}"));
    let explicit_path = base_dir.join("explicit.toml");
    fs::create_dir_all(&base_dir).unwrap();
    fs::write(&explicit_path, "[defaults]\nrunner = \"cc\"\n").unwrap();

    let old_env = std::env::var("CCC_CONFIG").ok();
    unsafe { std::env::set_var("CCC_CONFIG", &explicit_path) };
    let resolved = find_config_command_path();
    if let Some(value) = old_env {
        unsafe { std::env::set_var("CCC_CONFIG", value) };
    } else {
        unsafe { std::env::remove_var("CCC_CONFIG") };
    }

    assert_eq!(resolved, Some(explicit_path));
}

#[test]
fn test_find_config_command_path_prefers_project_local_then_xdg_then_home() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-command-order-{unique}"));
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let repo_root = base_dir.join("repo");
    let nested_cwd = repo_root.join("nested");
    fs::create_dir_all(&nested_cwd).unwrap();

    let project_path = repo_root.join(".ccc.toml");
    let xdg_path = xdg_root.join("ccc/config.toml");
    let home_path = home_root.join(".config/ccc/config.toml");
    fs::write(&project_path, "[defaults]\nrunner = \"cc\"\n").unwrap();
    fs::create_dir_all(xdg_path.parent().unwrap()).unwrap();
    fs::write(&xdg_path, "[defaults]\nrunner = \"k\"\n").unwrap();
    fs::create_dir_all(home_path.parent().unwrap()).unwrap();
    fs::write(&home_path, "[defaults]\nrunner = \"oc\"\n").unwrap();

    let old_cwd = std::env::current_dir().unwrap();
    let old_home = std::env::var("HOME").ok();
    let old_xdg = std::env::var("XDG_CONFIG_HOME").ok();
    let old_explicit = std::env::var("CCC_CONFIG").ok();

    std::env::set_current_dir(&nested_cwd).unwrap();
    unsafe { std::env::set_var("HOME", &home_root) };
    unsafe { std::env::set_var("XDG_CONFIG_HOME", &xdg_root) };
    unsafe { std::env::remove_var("CCC_CONFIG") };

    let resolved = find_config_command_path();

    std::env::set_current_dir(old_cwd).unwrap();
    if let Some(value) = old_home {
        unsafe { std::env::set_var("HOME", value) };
    } else {
        unsafe { std::env::remove_var("HOME") };
    }
    if let Some(value) = old_xdg {
        unsafe { std::env::set_var("XDG_CONFIG_HOME", value) };
    } else {
        unsafe { std::env::remove_var("XDG_CONFIG_HOME") };
    }
    if let Some(value) = old_explicit {
        unsafe { std::env::set_var("CCC_CONFIG", value) };
    } else {
        unsafe { std::env::remove_var("CCC_CONFIG") };
    }

    assert_eq!(resolved, Some(project_path));
}

#[test]
fn test_find_config_command_path_falls_back_when_ccc_config_is_missing() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-config-command-fallback-{unique}"));
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let xdg_path = xdg_root.join("ccc/config.toml");
    let missing_path = base_dir.join("missing.toml");

    fs::create_dir_all(xdg_path.parent().unwrap()).unwrap();
    fs::write(&xdg_path, "[defaults]\nrunner = \"k\"\n").unwrap();

    let old_home = std::env::var("HOME").ok();
    let old_xdg = std::env::var("XDG_CONFIG_HOME").ok();
    let old_explicit = std::env::var("CCC_CONFIG").ok();

    unsafe { std::env::set_var("HOME", &home_root) };
    unsafe { std::env::set_var("XDG_CONFIG_HOME", &xdg_root) };
    unsafe { std::env::set_var("CCC_CONFIG", &missing_path) };

    let resolved = find_config_command_path();

    if let Some(value) = old_home {
        unsafe { std::env::set_var("HOME", value) };
    } else {
        unsafe { std::env::remove_var("HOME") };
    }
    if let Some(value) = old_xdg {
        unsafe { std::env::set_var("XDG_CONFIG_HOME", value) };
    } else {
        unsafe { std::env::remove_var("XDG_CONFIG_HOME") };
    }
    if let Some(value) = old_explicit {
        unsafe { std::env::set_var("CCC_CONFIG", value) };
    } else {
        unsafe { std::env::remove_var("CCC_CONFIG") };
    }

    assert_eq!(resolved, Some(xdg_path));
}

#[test]
fn test_render_alias_block_omits_unset_keys_and_escapes_strings() {
    let alias = AliasDef {
        runner: Some("cc".to_string()),
        model: Some("claude \"quoted\"".to_string()),
        thinking: Some(3),
        show_thinking: Some(true),
        prompt: Some("Review\nchanges".to_string()),
        prompt_mode: Some("append".to_string()),
        ..AliasDef::default()
    };

    assert_eq!(
        render_alias_block("mm27", &alias).unwrap(),
        "[aliases.mm27]\n\
runner = \"cc\"\n\
model = \"claude \\\"quoted\\\"\"\n\
thinking = 3\n\
show_thinking = true\n\
prompt = \"Review\\nchanges\"\n\
prompt_mode = \"append\"\n"
    );
}

#[test]
fn test_upsert_alias_block_replaces_only_target_alias() {
    let content = "# keep me\n\
[defaults]\n\
runner = \"oc\"\n\
\n\
[aliases.mm27]\n\
runner = \"cc\"\n\
prompt = \"old\"\n\
\n\
[aliases.other]\n\
prompt = \"keep\"\n";
    let alias = AliasDef {
        runner: Some("k".to_string()),
        prompt: Some("new".to_string()),
        ..AliasDef::default()
    };

    assert_eq!(
        upsert_alias_block(content, "mm27", &alias).unwrap(),
        "# keep me\n\
[defaults]\n\
runner = \"oc\"\n\
\n\
[aliases.mm27]\n\
runner = \"k\"\n\
prompt = \"new\"\n\
\n\
[aliases.other]\n\
prompt = \"keep\"\n"
    );
}

#[test]
fn test_find_alias_write_path_global_ignores_project_and_prefers_xdg() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let base_dir = std::env::temp_dir().join(format!("ccc-rust-alias-write-{unique}"));
    let repo_root = base_dir.join("repo");
    let nested_cwd = repo_root.join("nested");
    fs::create_dir_all(&nested_cwd).unwrap();
    fs::write(repo_root.join(".ccc.toml"), "[aliases.local]\n").unwrap();
    let home_root = base_dir.join("home");
    let xdg_root = base_dir.join("xdg");
    let home_path = home_root.join(".config/ccc/config.toml");
    let xdg_path = xdg_root.join("ccc/config.toml");
    fs::create_dir_all(home_path.parent().unwrap()).unwrap();
    fs::create_dir_all(xdg_path.parent().unwrap()).unwrap();
    fs::write(&home_path, "[aliases.home]\n").unwrap();
    fs::write(&xdg_path, "[aliases.xdg]\n").unwrap();

    let old_cwd = std::env::current_dir().unwrap();
    let old_home = std::env::var("HOME").ok();
    let old_xdg = std::env::var("XDG_CONFIG_HOME").ok();
    let old_explicit = std::env::var("CCC_CONFIG").ok();

    std::env::set_current_dir(&nested_cwd).unwrap();
    unsafe { std::env::set_var("HOME", &home_root) };
    unsafe { std::env::set_var("XDG_CONFIG_HOME", &xdg_root) };
    unsafe { std::env::set_var("CCC_CONFIG", base_dir.join("custom.toml")) };

    let resolved = find_alias_write_path(true);

    std::env::set_current_dir(old_cwd).unwrap();
    if let Some(value) = old_home {
        unsafe { std::env::set_var("HOME", value) };
    } else {
        unsafe { std::env::remove_var("HOME") };
    }
    if let Some(value) = old_xdg {
        unsafe { std::env::set_var("XDG_CONFIG_HOME", value) };
    } else {
        unsafe { std::env::remove_var("XDG_CONFIG_HOME") };
    }
    if let Some(value) = old_explicit {
        unsafe { std::env::set_var("CCC_CONFIG", value) };
    } else {
        unsafe { std::env::remove_var("CCC_CONFIG") };
    }

    assert_eq!(resolved, xdg_path);
}

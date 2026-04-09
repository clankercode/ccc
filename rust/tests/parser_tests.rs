use call_coding_clis::*;

#[test]
fn test_parse_prompt_only() {
    let args: Vec<String> = vec!["hello world".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.prompt, "hello world");
    assert!(parsed.runner.is_none());
    assert!(parsed.thinking.is_none());
    assert!(parsed.alias.is_none());
}

#[test]
fn test_parse_runner_selector() {
    let args: Vec<String> = vec!["cc".into(), "fix bug".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cc"));
    assert_eq!(parsed.prompt, "fix bug");
}

#[test]
fn test_parse_runner_selector_codex_c() {
    let args: Vec<String> = vec!["c".into(), "fix bug".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("c"));
    assert_eq!(parsed.prompt, "fix bug");
}

#[test]
fn test_parse_runner_selector_codex_cx() {
    let args: Vec<String> = vec!["cx".into(), "fix bug".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cx"));
    assert_eq!(parsed.prompt, "fix bug");
}

#[test]
fn test_parse_thinking_level() {
    let args: Vec<String> = vec!["+2".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.thinking, Some(2));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_provider_model() {
    let args: Vec<String> = vec![":anthropic:claude-4".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.provider.as_deref(), Some("anthropic"));
    assert_eq!(parsed.model.as_deref(), Some("claude-4"));
}

#[test]
fn test_parse_alias() {
    let args: Vec<String> = vec!["@work".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.alias.as_deref(), Some("work"));
}

#[test]
fn test_parse_full_combo() {
    let args: Vec<String> = vec![
        "cc".into(),
        "+3".into(),
        ":anthropic:claude-4".into(),
        "@fast".into(),
        "fix tests".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cc"));
    assert_eq!(parsed.thinking, Some(3));
    assert_eq!(parsed.provider.as_deref(), Some("anthropic"));
    assert_eq!(parsed.model.as_deref(), Some("claude-4"));
    assert_eq!(parsed.alias.as_deref(), Some("fast"));
    assert_eq!(parsed.prompt, "fix tests");
}

#[test]
fn test_resolve_default_runner_is_opencode() {
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "opencode");
    assert!(argv.contains(&"run".to_string()));
    assert!(argv.contains(&"hello".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_claude_runner() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "claude");
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_codex_runner_via_c() {
    let parsed = ParsedArgs {
        runner: Some("c".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "codex");
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_codex_runner_via_cx() {
    let parsed = ParsedArgs {
        runner: Some("cx".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "codex");
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_roocode_runner_via_rc() {
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "roocode");
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_thinking_flags() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        thinking: Some(2),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert!(argv.contains(&"--thinking".to_string()));
    assert!(argv.contains(&"enabled".to_string()));
    assert!(argv.contains(&"--effort".to_string()));
    assert!(argv.contains(&"medium".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_thinking_zero_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        thinking: Some(0),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "claude".to_string(),
            "--thinking".to_string(),
            "disabled".to_string()
        ]
    );
    assert!(!argv.contains(&"--effort".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_kimi_thinking_flags() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        thinking: Some(4),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["kimi".to_string(), "--thinking".to_string()]);
    assert!(!argv.contains(&"--think".to_string()));
    assert!(!argv.contains(&"max".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_kimi_thinking_zero() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        thinking: Some(0),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["kimi".to_string(), "--no-thinking".to_string()]);
    assert!(!argv.contains(&"--thinking".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_model_flag() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        model: Some("claude-4".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert!(argv.contains(&"--model".to_string()));
    assert!(argv.contains(&"claude-4".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_provider_sets_env() {
    let parsed = ParsedArgs {
        provider: Some("anthropic".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (_, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        env.get("CCC_PROVIDER").map(|s| s.as_str()),
        Some("anthropic")
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_empty_prompt_errors() {
    let parsed = ParsedArgs {
        prompt: "   ".into(),
        ..Default::default()
    };
    assert!(resolve_command(&parsed, None).is_err());
}

#[test]
fn test_resolve_config_default_runner() {
    let config = CccConfig {
        default_runner: "cc".into(),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(argv[0], "claude");
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_config_default_thinking_for_claude() {
    let config = CccConfig {
        default_runner: "cc".into(),
        default_thinking: Some(1),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv[..5],
        [
            "claude".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_preset_agent() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "work".into(),
                AliasDef {
                    runner: Some("cc".into()),
                    thinking: Some(3),
                    model: Some("claude-4".into()),
                    agent: Some("reviewer".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("work".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(argv[0], "claude");
    assert!(argv.contains(&"--thinking".to_string()));
    assert!(argv.contains(&"enabled".to_string()));
    assert!(argv.contains(&"--effort".to_string()));
    assert!(argv.contains(&"high".to_string()));
    assert!(argv.contains(&"--agent".to_string()));
    assert!(argv.contains(&"reviewer".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_name_falls_back_to_agent() {
    let parsed = ParsedArgs {
        alias: Some("reviewer".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "opencode");
    assert!(argv.contains(&"--agent".to_string()));
    assert!(argv.contains(&"reviewer".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_agent_warning_when_runner_lacks_support() {
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        alias: Some("reviewer".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[0], "roocode");
    assert_eq!(
        warnings,
        vec![
            "warning: runner \"rc\" does not support agents; ignoring @reviewer".to_string()
        ]
    );
}

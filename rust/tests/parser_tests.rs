use call_coding_clis::*;

#[test]
fn test_sugar_parse_tokens_maps_common_cli_syntax() {
    let parsed = sugar::parse_tokens(["cc", ".fmt", "+3", "review this patch"])
        .expect("parse should succeed");

    assert_eq!(parsed.request.runner(), Some(RunnerKind::Claude));
    assert_eq!(parsed.request.output_mode(), Some(OutputMode::Formatted));
    assert_eq!(parsed.request.prompt(), "review this patch");
    assert!(parsed.warnings.is_empty());
}

#[test]
fn test_sugar_parse_tokens_supports_provider_model_sugar() {
    let parsed = sugar::parse_tokens(["c", ":openai:gpt-5.4-mini", "debug this"])
        .expect("parse should succeed");

    assert_eq!(parsed.request.runner(), Some(RunnerKind::Codex));
    assert_eq!(parsed.request.provider(), Some("openai"));
    assert_eq!(parsed.request.model(), Some("gpt-5.4-mini"));
    assert!(parsed.warnings.is_empty());
}

#[test]
fn test_sugar_parse_tokens_preserves_warnings_for_cleanup_session_compatibility() {
    let parsed = sugar::parse_tokens(["cr", "--cleanup-session", "review this patch"])
        .expect("parse should succeed");

    assert!(!parsed.warnings.is_empty());
    assert!(
        parsed
            .warnings
            .iter()
            .any(|warning| warning.contains("cleanup")),
        "expected a cleanup-session compatibility warning, got {:?}",
        parsed.warnings
    );
}

#[test]
fn test_parse_prompt_only() {
    let args: Vec<String> = vec!["hello world".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.prompt, "hello world");
    assert!(parsed.prompt_supplied);
    assert!(parsed.runner.is_none());
    assert!(parsed.thinking.is_none());
    assert!(parsed.show_thinking.is_none());
    assert!(parsed.sanitize_osc.is_none());
    assert!(!parsed.yolo);
    assert!(parsed.permission_mode.is_none());
    assert!(parsed.alias.is_none());
    assert!(!parsed.print_config);
}

#[test]
fn test_parse_print_config_flag() {
    let args: Vec<String> = vec!["--print-config".into()];
    let parsed = parse_args(&args);
    assert!(parsed.print_config);
    assert!(parsed.prompt.is_empty());
    assert!(!parsed.prompt_supplied);
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
fn test_parse_runner_selector_cursor_and_cu() {
    for selector in ["cursor", "cu"] {
        let args: Vec<String> = vec![selector.into(), "fix bug".into()];
        let parsed = parse_args(&args);
        assert_eq!(parsed.runner.as_deref(), Some(selector));
        assert_eq!(parsed.prompt, "fix bug");
    }
}

#[test]
fn test_parse_runner_selector_gemini_and_g() {
    for selector in ["gemini", "g"] {
        let args: Vec<String> = vec![selector.into(), "fix bug".into()];
        let parsed = parse_args(&args);
        assert_eq!(parsed.runner.as_deref(), Some(selector));
        assert_eq!(parsed.prompt, "fix bug");
    }
}

#[test]
fn test_parse_runner_selector_cr_remains_crush() {
    let args: Vec<String> = vec!["cr".into(), "fix bug".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cr"));
    assert_eq!(parsed.prompt, "fix bug");
}

#[test]
fn test_parse_unregistered_pi_as_prompt_text() {
    let args: Vec<String> = vec!["pi".into(), "fix bug".into()];
    let parsed = parse_args(&args);
    assert!(parsed.runner.is_none());
    assert_eq!(parsed.prompt, "pi fix bug");
}

#[test]
fn test_parse_thinking_level() {
    let args: Vec<String> = vec!["+2".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.thinking, Some(2));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_thinking_level_three() {
    let args: Vec<String> = vec!["+3".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.thinking, Some(3));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_thinking_level_four() {
    let args: Vec<String> = vec!["+4".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.thinking, Some(4));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_named_thinking_levels() {
    let cases = [
        ("+none", 0),
        ("+low", 1),
        ("+med", 2),
        ("+mid", 2),
        ("+medium", 2),
        ("+high", 3),
        ("+max", 4),
        ("+xhigh", 4),
    ];
    for (token, expected) in cases {
        let args: Vec<String> = vec![token.into(), "hello".into()];
        let parsed = parse_args(&args);
        assert_eq!(parsed.thinking, Some(expected));
        assert_eq!(parsed.prompt, "hello");
    }
}

#[test]
fn test_parse_show_thinking_flag() {
    let args: Vec<String> = vec!["--show-thinking".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.show_thinking, Some(true));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_no_show_thinking_flag() {
    let args: Vec<String> = vec!["--no-show-thinking".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.show_thinking, Some(false));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_sanitize_osc_flag() {
    let args: Vec<String> = vec!["--sanitize-osc".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.sanitize_osc, Some(true));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_no_sanitize_osc_flag() {
    let args: Vec<String> = vec!["--no-sanitize-osc".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.sanitize_osc, Some(false));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_output_mode_flag() {
    let args: Vec<String> = vec!["-o".into(), "stream-formatted".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.output_mode.as_deref(), Some("stream-formatted"));
}

#[test]
fn test_parse_output_mode_sugar() {
    let cases = [
        (".text", "text"),
        ("..text", "stream-text"),
        (".json", "json"),
        ("..json", "stream-json"),
        (".fmt", "formatted"),
        ("..fmt", "stream-formatted"),
    ];
    for (token, expected) in cases {
        let args: Vec<String> = vec![token.into(), "hello".into()];
        let parsed = parse_args(&args);
        assert_eq!(parsed.output_mode.as_deref(), Some(expected));
    }
}

#[test]
fn test_parse_forward_unknown_json_flag() {
    let args: Vec<String> = vec!["--forward-unknown-json".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert!(parsed.forward_unknown_json);
}

#[test]
fn test_parse_save_session_flag() {
    let args: Vec<String> = vec!["--save-session".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert!(parsed.save_session);
    assert!(!parsed.cleanup_session);
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_cleanup_session_flag() {
    let args: Vec<String> = vec!["--cleanup-session".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert!(parsed.cleanup_session);
    assert!(!parsed.save_session);
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
        "--yolo".into(),
        "+3".into(),
        ":anthropic:claude-4".into(),
        "@fast".into(),
        "fix tests".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cc"));
    assert_eq!(parsed.thinking, Some(3));
    assert!(parsed.yolo);
    assert_eq!(parsed.permission_mode.as_deref(), Some("yolo"));
    assert_eq!(parsed.provider.as_deref(), Some("anthropic"));
    assert_eq!(parsed.model.as_deref(), Some("claude-4"));
    assert_eq!(parsed.alias.as_deref(), Some("fast"));
    assert_eq!(parsed.prompt, "fix tests");
}

#[test]
fn test_parse_yolo_flags() {
    for token in ["--yolo", "-y"] {
        let args: Vec<String> = vec![token.into(), "hello".into()];
        let parsed = parse_args(&args);
        assert!(parsed.yolo);
        assert_eq!(parsed.permission_mode.as_deref(), Some("yolo"));
        assert_eq!(parsed.prompt, "hello");
    }
}

#[test]
fn test_parse_permission_mode_flag() {
    let args: Vec<String> = vec!["--permission-mode".into(), "auto".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.permission_mode.as_deref(), Some("auto"));
    assert!(!parsed.yolo);
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_permission_mode_yolo_sets_yolo() {
    let args: Vec<String> = vec!["--permission-mode".into(), "yolo".into(), "hello".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.permission_mode.as_deref(), Some("yolo"));
    assert!(parsed.yolo);
}

#[test]
fn test_parse_permission_mode_last_wins_over_yolo_sugar() {
    let args: Vec<String> = vec![
        "--yolo".into(),
        "--permission-mode".into(),
        "safe".into(),
        "hello".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(parsed.permission_mode.as_deref(), Some("safe"));
    assert!(!parsed.yolo);
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_control_tokens_in_any_order() {
    let args: Vec<String> = vec![
        "@fast".into(),
        ":anthropic:claude-4".into(),
        "--yolo".into(),
        "cc".into(),
        "+3".into(),
        "fix tests".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("cc"));
    assert_eq!(parsed.thinking, Some(3));
    assert!(parsed.yolo);
    assert_eq!(parsed.permission_mode.as_deref(), Some("yolo"));
    assert_eq!(parsed.provider.as_deref(), Some("anthropic"));
    assert_eq!(parsed.model.as_deref(), Some("claude-4"));
    assert_eq!(parsed.alias.as_deref(), Some("fast"));
    assert_eq!(parsed.prompt, "fix tests");
}

#[test]
fn test_parse_duplicate_pre_prompt_controls_use_last_value() {
    let args: Vec<String> = vec![
        "cc".into(),
        "k".into(),
        "--show-thinking".into(),
        "--no-show-thinking".into(),
        "@fast".into(),
        "@slow".into(),
        "hello".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(parsed.runner.as_deref(), Some("k"));
    assert_eq!(parsed.show_thinking, Some(false));
    assert_eq!(parsed.alias.as_deref(), Some("slow"));
    assert_eq!(parsed.prompt, "hello");
}

#[test]
fn test_parse_double_dash_forces_literal_prompt() {
    let args: Vec<String> = vec![
        "-y".into(),
        "--".into(),
        "+1".into(),
        "@agent".into(),
        ":model".into(),
    ];
    let parsed = parse_args(&args);
    assert!(parsed.yolo);
    assert_eq!(parsed.prompt, "+1 @agent :model");
}

#[test]
fn test_parse_double_dash_treats_print_config_as_prompt_text() {
    let args: Vec<String> = vec!["--".into(), "--print-config".into()];
    let parsed = parse_args(&args);
    assert!(!parsed.print_config);
    assert_eq!(parsed.prompt, "--print-config");
    assert!(parsed.prompt_supplied);
}

#[test]
fn test_parse_empty_string_prompt_counts_as_supplied() {
    let args: Vec<String> = vec!["".into()];
    let parsed = parse_args(&args);
    assert!(parsed.prompt.is_empty());
    assert!(parsed.prompt_supplied);
}

#[test]
fn test_parse_whitespace_prompt_counts_as_supplied() {
    let args: Vec<String> = vec!["   ".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.prompt, "   ");
    assert!(parsed.prompt_supplied);
}

#[test]
fn test_parse_permission_mode_missing_value_errors_in_resolve() {
    let args: Vec<String> = vec!["--permission-mode".into()];
    let parsed = parse_args(&args);
    assert_eq!(parsed.permission_mode.as_deref(), Some(""));
    assert!(resolve_command(&parsed, None).is_err());
}

#[test]
fn test_parse_save_session_and_cleanup_session_conflict() {
    let args: Vec<String> = vec![
        "--save-session".into(),
        "--cleanup-session".into(),
        "hello".into(),
    ];
    let parsed = parse_args(&args);
    assert_eq!(
        resolve_command(&parsed, None).unwrap_err(),
        "--save-session and --cleanup-session are mutually exclusive"
    );
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
    assert_eq!(argv[..2], ["claude", "-p"]);
    assert!(argv.contains(&"--no-session-persistence".to_string()));
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
    assert_eq!(argv[..2], ["codex", "exec"]);
    assert!(argv.contains(&"--ephemeral".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_save_session_preserves_old_claude_and_codex_argv() {
    let cases = [
        (
            ParsedArgs {
                runner: Some("cc".into()),
                save_session: true,
                prompt: "hello".into(),
                ..Default::default()
            },
            vec![
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "hello",
            ],
        ),
        (
            ParsedArgs {
                runner: Some("c".into()),
                save_session: true,
                prompt: "hello".into(),
                ..Default::default()
            },
            vec!["codex", "exec", "hello"],
        ),
    ];
    for (parsed, expected) in cases {
        let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
        assert_eq!(argv, expected);
        assert!(warnings.is_empty());
    }
}

#[test]
fn test_resolve_command_does_not_emit_default_persistence_warnings() {
    for runner in ["oc", "k", "cr", "rc"] {
        let parsed = ParsedArgs {
            runner: Some(runner.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let (_, _, warnings) = resolve_command(&parsed, None).unwrap();
        assert!(!warnings
            .iter()
            .any(|warning| warning.contains("may save this session")));
    }
}

#[test]
fn test_resolve_gemini_runner_via_g_uses_prompt_flag() {
    let parsed = ParsedArgs {
        runner: Some("g".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv, vec!["gemini", "--prompt", "hello"]);
    assert!(env.is_empty());
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_gemini_runner_long_name_with_model() {
    let parsed = ParsedArgs {
        runner: Some("gemini".into()),
        model: Some("gemini-2.5-pro".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        vec!["gemini", "--model", "gemini-2.5-pro", "--prompt", "hello"]
    );
    assert!(env.is_empty());
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_cleanup_session_warning_policy() {
    for runner in ["oc", "k"] {
        let parsed = ParsedArgs {
            runner: Some(runner.into()),
            cleanup_session: true,
            prompt: "hello".into(),
            ..Default::default()
        };
        let (_, _, warnings) = resolve_command(&parsed, None).unwrap();
        assert!(!warnings
            .iter()
            .any(|warning| warning.contains("may save this session")));
    }

    for (runner, display) in [
        ("cr", "crush"),
        ("rc", "roocode"),
        ("cu", "cursor"),
        ("g", "gemini"),
    ] {
        let parsed = ParsedArgs {
            runner: Some(runner.into()),
            cleanup_session: true,
            prompt: "hello".into(),
            ..Default::default()
        };
        let (_, _, warnings) = resolve_command(&parsed, None).unwrap();
        assert!(warnings.contains(&format!(
            "warning: runner \"{display}\" does not support automatic session cleanup; pass --save-session to allow saved sessions explicitly"
        )));
    }
}

#[test]
fn test_resolve_codex_runner_via_cx() {
    let parsed = ParsedArgs {
        runner: Some("cx".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["codex", "exec"]);
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_cursor_runner_via_cu() {
    let parsed = ParsedArgs {
        runner: Some("cu".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv, ["cursor-agent", "--print", "--trust", "hello"]);
    assert!(env.is_empty());
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_cursor_runner_long_name_with_model() {
    let parsed = ParsedArgs {
        runner: Some("cursor".into()),
        model: Some("gpt-5".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        [
            "cursor-agent",
            "--print",
            "--trust",
            "--model",
            "gpt-5",
            "hello"
        ]
    );
    assert!(env.is_empty());
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_cr_still_resolves_to_crush() {
    let parsed = ParsedArgs {
        runner: Some("cr".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv, ["crush", "run", "hello"]);
    assert!(env.is_empty());
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_codex_runner_with_model_uses_exec() {
    let parsed = ParsedArgs {
        runner: Some("c".into()),
        model: Some("gpt-5.4-mini".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        vec![
            "codex",
            "exec",
            "--model",
            "gpt-5.4-mini",
            "--ephemeral",
            "hello"
        ]
    );
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
fn test_resolve_thinking_level_three_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        thinking: Some(3),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert!(argv.contains(&"--thinking".to_string()));
    assert!(argv.contains(&"enabled".to_string()));
    assert!(argv.contains(&"--effort".to_string()));
    assert!(argv.contains(&"high".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_thinking_level_four_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        thinking: Some(4),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert!(argv.contains(&"--thinking".to_string()));
    assert!(argv.contains(&"enabled".to_string()));
    assert!(argv.contains(&"--effort".to_string()));
    assert!(argv.contains(&"max".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_show_thinking_for_opencode() {
    let parsed = ParsedArgs {
        show_thinking: Some(true),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string()
        ]
    );
    assert_eq!(argv.last().map(|s| s.as_str()), Some("hello"));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_sanitize_osc_defaults_on_for_formatted_modes() {
    let parsed = ParsedArgs {
        output_mode: Some("formatted".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(resolve_sanitize_osc(&parsed, None));
}

#[test]
fn test_resolve_sanitize_osc_defaults_off_after_output_mode_fallback() {
    let config = CccConfig {
        default_output_mode: "stream-formatted".into(),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(!resolve_sanitize_osc(&parsed, Some(&config)));
}

#[test]
fn test_resolve_sanitize_osc_defaults_off_for_raw_modes() {
    let parsed = ParsedArgs {
        output_mode: Some("json".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(!resolve_sanitize_osc(&parsed, None));
}

#[test]
fn test_resolve_sanitize_osc_uses_alias_default() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "review".into(),
                AliasDef {
                    sanitize_osc: Some(false),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("review".into()),
        output_mode: Some("formatted".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(!resolve_sanitize_osc(&parsed, Some(&config)));
}

#[test]
fn test_resolve_config_default_sanitize_osc() {
    let config = CccConfig {
        default_sanitize_osc: Some(false),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        output_mode: Some("formatted".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(!resolve_sanitize_osc(&parsed, Some(&config)));
}

#[test]
fn test_resolve_show_thinking_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        show_thinking: Some(true),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..6],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_show_thinking_for_kimi() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        show_thinking: Some(true),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["kimi".to_string(), "--thinking".to_string()]);
    assert_eq!(
        argv[argv.len() - 2..],
        ["--prompt".to_string(), "hello".to_string()]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_default_show_thinking_enables_opencode_thinking() {
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..3], ["opencode", "run", "--thinking"]);
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_default_thinking_effort_is_low_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..6],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_no_show_thinking_overrides_default_for_opencode() {
    let parsed = ParsedArgs {
        show_thinking: Some(false),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["opencode", "run"]);
    assert!(!argv.contains(&"--thinking".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_show_thinking_does_not_override_explicit_thinking() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        thinking: Some(3),
        show_thinking: Some(true),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..6],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "high".to_string()
        ]
    );
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
        argv[..4],
        [
            "claude".to_string(),
            "-p".to_string(),
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
    assert_eq!(
        argv[argv.len() - 2..],
        ["--prompt".to_string(), "hello".to_string()]
    );
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
    assert_eq!(
        argv[argv.len() - 2..],
        ["--prompt".to_string(), "hello".to_string()]
    );
    assert!(!argv.contains(&"--thinking".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_kimi_uses_prompt_flag() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        [
            "kimi".to_string(),
            "--thinking".to_string(),
            "--prompt".to_string(),
            "hello".to_string()
        ]
    );
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
fn test_resolve_opencode_sets_terminal_title_env() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (_, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        env.get("OPENCODE_DISABLE_TERMINAL_TITLE")
            .map(|s| s.as_str()),
        Some("true")
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
    assert_eq!(argv[..2], ["claude", "-p"]);
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
        argv[..6],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_config_default_show_thinking_for_claude() {
    let config = CccConfig {
        default_runner: "cc".into(),
        default_show_thinking: true,
        ..Default::default()
    };
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv[..6],
        [
            "claude".to_string(),
            "-p".to_string(),
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
    assert_eq!(argv[..2], ["claude", "-p"]);
    assert!(argv.contains(&"--thinking".to_string()));
    assert!(argv.contains(&"enabled".to_string()));
    assert!(argv.contains(&"--effort".to_string()));
    assert!(argv.contains(&"high".to_string()));
    assert!(argv.contains(&"--agent".to_string()));
    assert!(argv.contains(&"reviewer".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_prompt_fills_missing_prompt() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "   ".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec!["opencode", "run", "--thinking", "Commit all changes"]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_explicit_prompt_overrides_alias_prompt() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "Write the commit summary".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "Write the commit summary".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_prompt_mode_prepend_uses_newline_separator() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    prompt_mode: Some("prepend".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "Include the failing tests".into(),
        prompt_supplied: true,
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "Commit all changes\nInclude the failing tests".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_prompt_mode_append_uses_newline_separator() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    prompt_mode: Some("append".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "Include the failing tests".into(),
        prompt_supplied: true,
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "Include the failing tests\nCommit all changes".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_prompt_mode_requires_supplied_prompt() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    prompt_mode: Some("append".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: String::new(),
        ..Default::default()
    };
    let err = resolve_command(&parsed, Some(&config)).unwrap_err();
    assert_eq!(
        err,
        "prompt_mode append requires an explicit prompt argument"
    );
}

#[test]
fn test_resolve_alias_prompt_mode_allows_explicit_empty_prompt() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    prompt_mode: Some("prepend".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: String::new(),
        prompt_supplied: true,
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "Commit all changes".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_alias_prompt_mode_requires_non_empty_alias_prompt() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("   ".into()),
                    prompt_mode: Some("append".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "Add tests".into(),
        prompt_supplied: true,
        ..Default::default()
    };
    let err = resolve_command(&parsed, Some(&config)).unwrap_err();
    assert_eq!(err, "prompt_mode append requires aliases.commit.prompt");
}

#[test]
fn test_resolve_alias_prompt_mode_rejects_invalid_value() {
    let config = CccConfig {
        aliases: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                "commit".into(),
                AliasDef {
                    prompt: Some("Commit all changes".into()),
                    prompt_mode: Some("replace".into()),
                    ..Default::default()
                },
            );
            m
        },
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("commit".into()),
        prompt: "Add tests".into(),
        prompt_supplied: true,
        ..Default::default()
    };
    let err = resolve_command(&parsed, Some(&config)).unwrap_err();
    assert_eq!(err, "prompt_mode must be one of: default, prepend, append");
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
fn test_unresolved_alias_matching_runner_selector_selects_runner() {
    let config = CccConfig {
        default_runner: "k".into(),
        default_output_mode: "stream-formatted".into(),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        alias: Some("k".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv,
        vec![
            "kimi",
            "--print",
            "--output-format",
            "stream-json",
            "--thinking",
            "--prompt",
            "hello"
        ]
    );
    assert!(!argv.contains(&"--agent".to_string()));
    assert!(warnings.is_empty());
}

#[test]
fn test_explicit_runner_keeps_runner_like_alias_as_agent() {
    let args: Vec<String> = vec!["oc".into(), "@k".into(), "hello".into()];
    let parsed = parse_args(&args);
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "--agent".to_string(),
            "k".to_string(),
            "hello".to_string(),
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_configured_alias_named_like_runner_selector_wins() {
    let mut config = CccConfig::default();
    config.aliases.insert(
        "k".into(),
        AliasDef {
            runner: Some("oc".into()),
            agent: Some("specialist".into()),
            ..Default::default()
        },
    );
    let parsed = ParsedArgs {
        alias: Some("k".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, Some(&config)).unwrap();
    assert_eq!(
        argv[..5],
        ["opencode", "run", "--thinking", "--agent", "specialist"]
    );
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
        vec!["warning: runner \"rc\" does not support agents; ignoring @reviewer".to_string()]
    );
}

#[test]
fn test_resolve_yolo_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..7],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string(),
            "--dangerously-skip-permissions".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_yolo_for_codex() {
    let parsed = ParsedArgs {
        runner: Some("c".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "codex".to_string(),
            "exec".to_string(),
            "--dangerously-bypass-approvals-and-sandbox".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_yolo_for_kimi() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "kimi".to_string(),
            "--thinking".to_string(),
            "--yolo".to_string()
        ]
    );
    assert_eq!(
        argv[argv.len() - 2..],
        ["--prompt".to_string(), "hello".to_string()]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_yolo_for_crush() {
    let parsed = ParsedArgs {
        runner: Some("cr".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv[..2], ["crush".to_string(), "run".to_string()]);
    assert_eq!(
        warnings,
        vec!["warning: runner \"crush\" does not support yolo mode in non-interactive run mode; ignoring --yolo".to_string()]
    );
}

#[test]
fn test_resolve_yolo_for_opencode_uses_env_override() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        vec![
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "hello".to_string()
        ]
    );
    assert_eq!(
        env.get("OPENCODE_CONFIG_CONTENT").map(|s| s.as_str()),
        Some("{\"permission\":\"allow\"}")
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_yolo_for_roocode_warns() {
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv, vec!["roocode".to_string(), "hello".to_string()]);
    assert_eq!(
        warnings,
        vec!["warning: runner \"roocode\" yolo mode is unverified; ignoring --yolo".to_string()]
    );
}

#[test]
fn test_resolve_yolo_for_cursor() {
    let parsed = ParsedArgs {
        runner: Some("cu".into()),
        yolo: true,
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        ["cursor-agent", "--print", "--trust", "--yolo", "hello"]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_safe_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        permission_mode: Some("safe".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..8],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string(),
            "--permission-mode".to_string(),
            "default".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_safe_for_opencode_uses_ask_override() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        permission_mode: Some("safe".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        [
            "opencode".to_string(),
            "run".to_string(),
            "--thinking".to_string(),
            "hello".to_string()
        ]
    );
    assert_eq!(
        env.get("OPENCODE_CONFIG_CONTENT").map(|s| s.as_str()),
        Some("{\"permission\":\"ask\"}")
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_safe_for_roocode_warns() {
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        permission_mode: Some("safe".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(argv, ["roocode".to_string(), "hello".to_string()]);
    assert_eq!(
        warnings,
        vec![
            "warning: runner \"roocode\" safe mode is unverified; leaving default permissions unchanged"
                .to_string()
        ]
    );
}

#[test]
fn test_resolve_permission_modes_for_cursor() {
    let cases = [
        (
            "safe",
            vec![
                "cursor-agent",
                "--print",
                "--trust",
                "--sandbox",
                "enabled",
                "hello",
            ],
            Vec::<String>::new(),
        ),
        (
            "plan",
            vec![
                "cursor-agent",
                "--print",
                "--trust",
                "--mode",
                "plan",
                "hello",
            ],
            Vec::<String>::new(),
        ),
        (
            "auto",
            vec!["cursor-agent", "--print", "--trust", "hello"],
            vec![
                "warning: runner \"cu\" does not support permission mode \"auto\"; ignoring it"
                    .to_string(),
            ],
        ),
    ];
    for (mode, expected_argv, expected_warnings) in cases {
        let parsed = ParsedArgs {
            runner: Some("cu".into()),
            permission_mode: Some(mode.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
        assert_eq!(argv, expected_argv);
        assert_eq!(warnings, expected_warnings);
    }
}

#[test]
fn test_resolve_permission_modes_for_gemini() {
    let cases = [
        (
            "safe",
            vec![
                "gemini",
                "--approval-mode",
                "default",
                "--sandbox",
                "--prompt",
                "hello",
            ],
        ),
        (
            "auto",
            vec![
                "gemini",
                "--approval-mode",
                "auto_edit",
                "--prompt",
                "hello",
            ],
        ),
        (
            "yolo",
            vec!["gemini", "--approval-mode", "yolo", "--prompt", "hello"],
        ),
        (
            "plan",
            vec!["gemini", "--approval-mode", "plan", "--prompt", "hello"],
        ),
    ];
    for (mode, expected_argv) in cases {
        let parsed = ParsedArgs {
            runner: Some("g".into()),
            permission_mode: Some(mode.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let (argv, env, warnings) = resolve_command(&parsed, None).unwrap();
        assert_eq!(argv, expected_argv);
        assert!(env.is_empty());
        assert!(warnings.is_empty());
    }
}

#[test]
fn test_resolve_permission_mode_auto_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        permission_mode: Some("auto".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..8],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string(),
            "--permission-mode".to_string(),
            "auto".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_auto_for_codex() {
    let parsed = ParsedArgs {
        runner: Some("c".into()),
        permission_mode: Some("auto".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "codex".to_string(),
            "exec".to_string(),
            "--full-auto".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_plan_for_claude() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        permission_mode: Some("plan".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..8],
        [
            "claude".to_string(),
            "-p".to_string(),
            "--thinking".to_string(),
            "enabled".to_string(),
            "--effort".to_string(),
            "low".to_string(),
            "--permission-mode".to_string(),
            "plan".to_string()
        ]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_plan_for_kimi() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        permission_mode: Some("plan".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv[..3],
        [
            "kimi".to_string(),
            "--thinking".to_string(),
            "--plan".to_string()
        ]
    );
    assert_eq!(
        argv[argv.len() - 2..],
        ["--prompt".to_string(), "hello".to_string()]
    );
    assert!(warnings.is_empty());
}

#[test]
fn test_resolve_permission_mode_auto_warns_for_kimi() {
    let parsed = ParsedArgs {
        runner: Some("k".into()),
        permission_mode: Some("auto".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let (argv, _, warnings) = resolve_command(&parsed, None).unwrap();
    assert_eq!(
        argv,
        [
            "kimi".to_string(),
            "--thinking".to_string(),
            "--prompt".to_string(),
            "hello".to_string()
        ]
    );
    assert_eq!(
        warnings,
        vec![
            "warning: runner \"k\" does not support permission mode \"auto\"; ignoring it"
                .to_string()
        ]
    );
}

#[test]
fn test_resolve_output_mode_defaults_to_text() {
    let parsed = ParsedArgs {
        prompt: "hello".into(),
        ..Default::default()
    };
    assert_eq!(resolve_output_mode(&parsed, None).unwrap(), "text");
}

#[test]
fn test_resolve_output_mode_uses_alias_default() {
    let mut config = CccConfig::default();
    config.aliases.insert(
        "review".into(),
        AliasDef {
            output_mode: Some("formatted".into()),
            ..Default::default()
        },
    );
    let parsed = ParsedArgs {
        alias: Some("review".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert_eq!(
        resolve_output_mode(&parsed, Some(&config)).unwrap(),
        "formatted"
    );
}

#[test]
fn test_resolve_claude_stream_formatted_output_plan() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        output_mode: Some("stream-formatted".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, None).unwrap();
    assert!(plan.stream);
    assert!(plan.formatted);
    assert_eq!(plan.schema.as_deref(), Some("claude-code"));
    assert_eq!(
        plan.argv_flags,
        vec![
            "--verbose",
            "--output-format",
            "stream-json",
            "--include-partial-messages"
        ]
    );
}

#[test]
fn test_resolve_opencode_json_output_plan() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        output_mode: Some("json".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, None).unwrap();
    assert_eq!(plan.schema.as_deref(), Some("opencode"));
    assert_eq!(plan.argv_flags, vec!["--format", "json"]);
}

#[test]
fn test_resolve_opencode_stream_formatted_output_plan() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        output_mode: Some("stream-formatted".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, None).unwrap();
    assert!(plan.stream);
    assert!(plan.formatted);
    assert_eq!(plan.schema.as_deref(), Some("opencode"));
    assert_eq!(plan.argv_flags, vec!["--format", "json"]);
}

#[test]
fn test_resolve_opencode_stream_json_output_plan() {
    let parsed = ParsedArgs {
        runner: Some("oc".into()),
        output_mode: Some("stream-json".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, None).unwrap();
    assert!(plan.stream);
    assert!(!plan.formatted);
    assert_eq!(plan.schema.as_deref(), Some("opencode"));
    assert_eq!(plan.argv_flags, vec!["--format", "json"]);
}

#[test]
fn test_resolve_codex_output_plans() {
    let cases = [
        ("json", false, false),
        ("stream-json", true, false),
        ("formatted", false, true),
        ("stream-formatted", true, true),
    ];
    for (mode, stream, formatted) in cases {
        let parsed = ParsedArgs {
            runner: Some("c".into()),
            output_mode: Some(mode.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let plan = resolve_output_plan(&parsed, None).unwrap();
        assert_eq!(plan.stream, stream);
        assert_eq!(plan.formatted, formatted);
        assert_eq!(plan.schema.as_deref(), Some("codex"));
        assert_eq!(plan.argv_flags, vec!["--json"]);
    }
}

#[test]
fn test_resolve_cursor_output_plans() {
    let cases = [
        ("json", false, false, vec!["--output-format", "json"]),
        (
            "stream-json",
            true,
            false,
            vec!["--output-format", "stream-json"],
        ),
        (
            "formatted",
            false,
            true,
            vec!["--output-format", "stream-json"],
        ),
        (
            "stream-formatted",
            true,
            true,
            vec!["--output-format", "stream-json"],
        ),
    ];
    for (mode, stream, formatted, flags) in cases {
        let parsed = ParsedArgs {
            runner: Some("cu".into()),
            output_mode: Some(mode.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let plan = resolve_output_plan(&parsed, None).unwrap();
        assert_eq!(plan.stream, stream);
        assert_eq!(plan.formatted, formatted);
        assert_eq!(plan.schema.as_deref(), Some("cursor-agent"));
        assert_eq!(plan.argv_flags, flags);
    }
}

#[test]
fn test_resolve_gemini_output_plans() {
    let cases = [
        ("json", false, false, vec!["--output-format", "json"]),
        (
            "stream-json",
            true,
            false,
            vec!["--output-format", "stream-json"],
        ),
        (
            "formatted",
            false,
            true,
            vec!["--output-format", "stream-json"],
        ),
        (
            "stream-formatted",
            true,
            true,
            vec!["--output-format", "stream-json"],
        ),
    ];
    for (mode, stream, formatted, flags) in cases {
        let parsed = ParsedArgs {
            runner: Some("g".into()),
            output_mode: Some(mode.into()),
            prompt: "hello".into(),
            ..Default::default()
        };
        let plan = resolve_output_plan(&parsed, None).unwrap();
        assert_eq!(plan.stream, stream);
        assert_eq!(plan.formatted, formatted);
        assert_eq!(plan.schema.as_deref(), Some("gemini"));
        assert_eq!(plan.argv_flags, flags);
    }
}

#[test]
fn test_configured_unsupported_output_mode_falls_back_to_text() {
    let config = CccConfig {
        default_output_mode: "stream-formatted".into(),
        ..Default::default()
    };
    let parsed = ParsedArgs {
        runner: Some("rc".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, Some(&config)).unwrap();
    assert_eq!(plan.mode, "text");
    assert!(plan.argv_flags.is_empty());
    assert_eq!(
        plan.warnings,
        vec![
            "warning: runner \"roocode\" does not support configured output mode \"stream-formatted\"; falling back to \"text\""
        ]
    );
}

#[test]
fn test_alias_unsupported_output_mode_falls_back_to_text() {
    let mut config = CccConfig::default();
    config.aliases.insert(
        "fast".into(),
        AliasDef {
            runner: Some("rc".into()),
            output_mode: Some("stream-formatted".into()),
            ..Default::default()
        },
    );
    let parsed = ParsedArgs {
        alias: Some("fast".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    let plan = resolve_output_plan(&parsed, Some(&config)).unwrap();
    assert_eq!(plan.runner_name, "rc");
    assert_eq!(plan.mode, "text");
    assert_eq!(
        plan.warnings,
        vec![
            "warning: runner \"roocode\" does not support alias output mode \"stream-formatted\"; falling back to \"text\""
        ]
    );
}

#[test]
fn test_resolve_invalid_permission_mode_errors() {
    let parsed = ParsedArgs {
        runner: Some("cc".into()),
        permission_mode: Some("wild".into()),
        prompt: "hello".into(),
        ..Default::default()
    };
    assert!(resolve_command(&parsed, None).is_err());
}

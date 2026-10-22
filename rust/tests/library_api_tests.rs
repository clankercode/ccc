use call_coding_clis::{
    parse_tokens_with_config, sugar, AliasDef, CccConfig, Client, CommandSpec, CompletedRun, Event,
    OutputMode, Request, Run, Runner, RunnerKind, Transcript,
};

#[test]
fn library_api_tests_request_builder_sets_expected_fields() {
    let request = Request::new("review this patch")
        .with_runner(RunnerKind::Codex)
        .with_provider("openai")
        .with_model("gpt-5.4-mini")
        .with_output_mode(OutputMode::StreamFormatted);

    assert_eq!(request.prompt(), "review this patch");
    assert_eq!(request.runner(), Some(RunnerKind::Codex));
    assert_eq!(request.provider(), Some("openai"));
    assert_eq!(request.model(), Some("gpt-5.4-mini"));
    assert_eq!(request.output_mode(), Some(OutputMode::StreamFormatted));
}

#[test]
fn library_api_tests_standalone_builder_and_token_roundtrip() {
    assert_eq!(Request::new("hello").standalone(), None);
    for (runner, token) in [(RunnerKind::Codex, "c"), (RunnerKind::OpenCode, "oc")] {
        for (controls, expected) in [
            (vec!["--standalone"], true),
            (vec!["--no-daemon"], true),
            (vec!["--no-standalone"], false),
            (vec!["--standalone", "--no-standalone"], false),
            (vec!["--no-standalone", "--no-daemon"], true),
        ] {
            let tokens = [vec![token], controls, vec!["hello"]].concat();
            let parsed = sugar::parse_tokens(tokens).unwrap();
            let request = Request::new("hello")
                .with_runner(runner)
                .with_standalone(expected);
            assert_eq!(parsed.request, request);
            assert_eq!(request.standalone(), Some(expected));
            let plan = Client::new().plan(&request).unwrap();
            assert_eq!(plan.runner(), runner);
            let argv = &plan.command_spec().argv;
            if runner == RunnerKind::Codex {
                if expected {
                    assert_eq!(argv[..3], ["codex", "--no-daemon", "exec"]);
                    assert_eq!(argv.iter().filter(|arg| *arg == "--no-daemon").count(), 1);
                } else {
                    assert_eq!(argv[..2], ["codex", "exec"]);
                    assert!(!argv.iter().any(|arg| arg == "--no-daemon"));
                }
            } else {
                assert_eq!(argv[..2], ["opencode", "run"]);
                assert_eq!(argv.iter().any(|arg| arg == "--standalone"), expected);
            }
        }
    }
    let request = Request::new("hello")
        .with_runner(RunnerKind::Codex)
        .with_standalone(true)
        .with_standalone(false);
    assert_eq!(request.standalone(), Some(false));
    let client = Client::new().with_config(CccConfig {
        default_standalone: Some(true),
        ..CccConfig::default()
    });
    assert!(!client
        .plan(&request)
        .unwrap()
        .command_spec()
        .argv
        .iter()
        .any(|arg| arg == "--no-daemon"));
}

#[test]
fn library_api_tests_service_tier_builder_last_control_wins() {
    let base = Request::new("hello").with_runner(RunnerKind::Codex);
    for (request, expected) in [
        (base.clone(), None),
        (base.clone().with_service_tier("PrIoRiTy"), Some("priority")),
        (
            base.clone().with_fast(true).with_service_tier("ultrafast"),
            Some("ultrafast"),
        ),
        (
            base.clone().with_service_tier("ultrafast").with_fast(true),
            Some("fast"),
        ),
        (
            base.with_service_tier("priority").with_fast(false),
            Some("default"),
        ),
    ] {
        let plan = Client::new().plan(&request).unwrap();
        let tiers: Vec<_> = plan
            .command_spec()
            .argv
            .windows(2)
            .filter(|pair| pair[0] == "-c" && pair[1].starts_with("service_tier="))
            .map(|pair| pair[1].as_str())
            .collect();
        let expected: Vec<_> = expected
            .into_iter()
            .map(|tier| format!("service_tier=\"{tier}\""))
            .collect();
        assert_eq!(tiers, expected);
    }
}

#[test]
fn library_api_tests_service_tier_survives_parsed_request_roundtrip() {
    for (controls, tier) in [
        (vec!["--service-tier", "PrIoRiTy"], "priority"),
        (vec!["--fast", "--service-tier", "default"], "default"),
        (vec!["--service-tier", "ultrafast", "--fast"], "fast"),
        (vec!["--service-tier", "fast", "--no-fast"], "default"),
    ] {
        let tokens = [vec!["c"], controls, vec!["hello"]].concat();
        let parsed = sugar::parse_tokens(tokens).unwrap();
        let plan = Client::new().plan(&parsed.request).unwrap();
        assert!(plan
            .command_spec()
            .argv
            .windows(2)
            .any(|pair| pair == ["-c", &format!("service_tier=\"{tier}\"")]));
        if tier == "priority" {
            assert_eq!(parsed.request.service_tier(), Some("priority"));
        }
    }
}

#[test]
fn library_api_tests_service_tier_validation_includes_unsupported_runners() {
    for runner in [RunnerKind::Codex, RunnerKind::Claude] {
        let request = Request::new("hello")
            .with_runner(runner)
            .with_service_tier("turbo");
        let error = Client::new().plan(&request).unwrap_err().to_string();
        assert!(error.contains("service tier must be one of: default, fast, priority, ultrafast"));
    }
    for tokens in [
        vec!["c", "--service-tier", "turbo", "--fast", "hello"],
        vec![
            "c",
            "--service-tier",
            "turbo",
            "--service-tier",
            "fast",
            "hello",
        ],
    ] {
        assert!(sugar::parse_tokens(tokens).is_err());
    }
}

#[test]
fn library_api_tests_request_preserves_ultra_effort() {
    let builder = Request::new("hello")
        .with_runner(RunnerKind::Codex)
        .with_thinking(6);
    let parsed = sugar::parse_tokens(["c", "+ultra", "hello"]).unwrap();
    assert_eq!(parsed.request, builder);
    let plan = Client::new().plan(&builder).unwrap();
    assert!(plan
        .command_spec()
        .argv
        .windows(2)
        .any(|pair| pair == ["-c", "model_reasoning_effort=ultra"]));
}

#[test]
fn library_api_tests_build_prompt_spec_uses_opencode_run() {
    let spec = call_coding_clis::build_prompt_spec(" hello ").unwrap();
    assert_eq!(spec.argv, ["opencode", "run", "hello"]);
}

#[test]
fn library_api_tests_sugar_parse_tokens_supports_provider_model_sugar() {
    let parsed = sugar::parse_tokens(["c", ":openai:gpt-5.4-mini", "debug this"])
        .expect("parse should succeed");

    assert_eq!(parsed.request.runner(), Some(RunnerKind::Codex));
    assert_eq!(parsed.request.provider(), Some("openai"));
    assert_eq!(parsed.request.model(), Some("gpt-5.4-mini"));
}

#[test]
fn library_api_tests_parse_tokens_with_config_uses_explicit_defaults() {
    let config = CccConfig {
        default_runner: "codex".to_string(),
        ..CccConfig::default()
    };
    let parsed = parse_tokens_with_config(["debug this"], &config).expect("parse should succeed");
    let plan = Client::new()
        .with_config(config)
        .plan(&parsed.request)
        .expect("plan should resolve");

    assert_eq!(plan.runner(), RunnerKind::Codex);
}

#[test]
fn library_api_tests_client_plan_resolves_to_non_empty_command_spec() {
    let client = Client::new();
    let request = Request::new("explain this module").with_runner(RunnerKind::OpenCode);
    let plan = client.plan(&request).expect("plan should resolve");

    assert!(!plan.command_spec().argv.is_empty());
    assert_eq!(plan.runner(), RunnerKind::OpenCode);
}

#[test]
fn library_api_tests_client_plan_preserves_runner_args_before_prompt() {
    let client = Client::new();
    let request = Request::new("hello")
        .with_runner(RunnerKind::Kimi)
        .with_runner_arg("--max-steps-per-turn")
        .with_runner_arg("9999");
    let plan = client.plan(&request).expect("plan should resolve");
    let argv = &plan.command_spec().argv;
    let prompt_index = argv.iter().position(|arg| arg == "--prompt").unwrap();

    assert_eq!(argv[prompt_index - 2], "--max-steps-per-turn");
    assert_eq!(argv[prompt_index - 1], "9999");
    assert_eq!(argv[prompt_index + 1], "hello");
}

#[test]
fn library_api_tests_client_plan_preserves_provider_only_request() {
    let client = Client::new();
    let request = Request::new("explain this module")
        .with_runner(RunnerKind::OpenCode)
        .with_provider("openai");
    let plan = client.plan(&request).expect("plan should resolve");

    assert_eq!(
        plan.command_spec()
            .env
            .get("CCC_PROVIDER")
            .map(|s| s.as_str()),
        Some("openai")
    );
}

#[test]
fn library_api_tests_client_with_config_uses_injected_defaults() {
    let client = Client::new().with_config(CccConfig {
        default_runner: "codex".to_string(),
        ..CccConfig::default()
    });
    let request = Request::new("explain this module");
    let plan = client.plan(&request).expect("plan should resolve");

    assert_eq!(plan.runner(), RunnerKind::Codex);
    assert_eq!(
        plan.command_spec().argv.first().map(|s| s.as_str()),
        Some("codex")
    );
}

#[test]
fn library_api_tests_client_plan_recognizes_pi_alias_runner() {
    let mut config = CccConfig::default();
    config.aliases.insert(
        "pi-mimo25p".to_string(),
        AliasDef {
            runner: Some("pi".to_string()),
            provider: Some("xiaomi-token-plan-sgp".to_string()),
            model: Some("mimo-v2.5-pro".to_string()),
            thinking: Some(3),
            output_mode: Some("stream-text".to_string()),
            ..AliasDef::default()
        },
    );
    let parsed = parse_tokens_with_config(["@pi-mimo25p", "reply HI123"], &config)
        .expect("parse should succeed");
    let plan = Client::new()
        .with_config(config)
        .plan(&parsed.request)
        .expect("plan should resolve");

    assert_eq!(plan.runner(), RunnerKind::Pi);
    assert_eq!(
        plan.command_spec().argv,
        vec![
            "pi",
            "-p",
            "--thinking",
            "high",
            "--provider",
            "xiaomi-token-plan-sgp",
            "--model",
            "mimo-v2.5-pro",
            "--no-session",
            "reply HI123",
        ]
    );
}

#[test]
fn library_api_tests_client_plan_applies_pi_binary_override() {
    let plan = Client::new()
        .with_binary_override(RunnerKind::Pi, "/tmp/mock-pi")
        .plan(&Request::new("hello").with_runner(RunnerKind::Pi))
        .expect("plan should resolve");

    assert_eq!(plan.runner(), RunnerKind::Pi);
    assert_eq!(
        plan.command_spec().argv.first().map(|s| s.as_str()),
        Some("/tmp/mock-pi")
    );
}

#[test]
fn library_api_tests_typed_transcript_and_run_surface_are_available() {
    let transcript = Transcript {
        events: vec![Event::Text("hello".into())],
        final_text: "hello".into(),
        session_id: Some("sess-abc".into()),
        usage: Default::default(),
        error: None,
        unknown_json_lines: vec!["{\"mystery\":true}".into()],
    };

    assert_eq!(transcript.final_text, "hello");
    assert_eq!(transcript.unknown_json_lines.len(), 1);
}

#[test]
fn library_api_tests_client_run_exposes_parsed_output_for_formatted_modes() {
    let client =
        Client::new().with_runtime_runner(Runner::with_executor(Box::new(|spec| {
            CompletedRun::new(spec.argv, 0, "{\"response\":\"hello\"}\n", String::new())
        })));
    let request = Request::new("hello")
        .with_runner(RunnerKind::OpenCode)
        .with_output_mode(OutputMode::Formatted);

    let run: Run = client.run(&request).expect("run should succeed");

    assert_eq!(run.final_text(), "hello");
    assert!(run.parsed_output().is_some());
}

#[cfg(unix)]
#[test]
fn library_api_tests_runner_run_with_timeout_kills_slow_child() {
    let spec = CommandSpec::new(["/bin/sh", "-c", "sleep 30"]).with_timeout_secs(1);
    let start = std::time::Instant::now();
    let result = Runner::new().run(spec);
    let elapsed = start.elapsed();

    assert!(result.timed_out, "expected timed_out to be true");
    // Must die well before the full sleep; allow headroom for slow CI hosts.
    assert!(
        elapsed < std::time::Duration::from_secs(5),
        "expected runner to exit under 5s, got {elapsed:?}"
    );
}

#[test]
fn library_api_tests_client_run_returns_tool_failed_for_non_zero_exit() {
    let client =
        Client::new().with_runtime_runner(Runner::with_executor(Box::new(|spec| {
            CompletedRun::new(spec.argv, 7, String::new(), "runner failed")
        })));
    let request = Request::new("hello")
        .with_runner(RunnerKind::OpenCode)
        .with_output_mode(OutputMode::Text);

    let error = client.run(&request).expect_err("run should fail");

    match error {
        call_coding_clis::Error::ToolFailed { exit_code, stderr } => {
            assert_eq!(exit_code, 7);
            assert_eq!(stderr, "runner failed");
        }
        other => panic!("expected ToolFailed error, got {other}"),
    }
}

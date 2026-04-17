use call_coding_clis::{
    parse_tokens_with_config, sugar, Client, CompletedRun, CccConfig, Event, OutputMode, Request,
    Run, Runner, RunnerKind, Transcript,
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
fn library_api_tests_client_with_config_uses_injected_defaults() {
    let client = Client::new().with_config(CccConfig {
        default_runner: "codex".to_string(),
        ..CccConfig::default()
    });
    let request = Request::new("explain this module");
    let plan = client.plan(&request).expect("plan should resolve");

    assert_eq!(plan.runner(), RunnerKind::Codex);
    assert_eq!(plan.command_spec().argv.first().map(|s| s.as_str()), Some("codex"));
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
    let client = Client::new().with_runtime_runner(Runner::with_executor(Box::new(|spec| CompletedRun {
        argv: spec.argv,
        exit_code: 0,
        stdout: "{\"response\":\"hello\"}\n".into(),
        stderr: String::new(),
    })));
    let request = Request::new("hello")
        .with_runner(RunnerKind::OpenCode)
        .with_output_mode(OutputMode::Formatted);

    let run: Run = client.run(&request).expect("run should succeed");

    assert_eq!(run.final_text(), "hello");
    assert!(run.parsed_output().is_some());
}

#[test]
fn library_api_tests_client_run_returns_tool_failed_for_non_zero_exit() {
    let client = Client::new().with_runtime_runner(Runner::with_executor(Box::new(|spec| CompletedRun {
        argv: spec.argv,
        exit_code: 7,
        stdout: String::new(),
        stderr: "runner failed".into(),
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

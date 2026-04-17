use call_coding_clis::{Client, CccConfig, OutputMode, Request, RunnerKind};

#[test]
fn library_api_tests_request_builder_sets_expected_fields() {
    let request = Request::new("review this patch")
        .with_runner(RunnerKind::Codex)
        .with_model("gpt-5.4-mini")
        .with_output_mode(OutputMode::StreamFormatted);

    assert_eq!(request.prompt(), "review this patch");
    assert_eq!(request.runner(), Some(RunnerKind::Codex));
    assert_eq!(request.model(), Some("gpt-5.4-mini"));
    assert_eq!(request.output_mode(), Some(OutputMode::StreamFormatted));
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

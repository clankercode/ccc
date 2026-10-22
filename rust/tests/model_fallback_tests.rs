use call_coding_clis::{
    AliasDef, CccConfig, Client, CommandSpec, CompletedRun, OutputMode, Request, Run, Runner,
    RunnerKind,
};
use std::sync::{Arc, Mutex};

const PRIMARY: &str = "gpt-6.1-sol";
const FINAL_MODEL: &str = "glm-5.3-flash";
const TIER_WARNING: &str =
    "warning: runner \"grok\" does not support service tiers; ignoring service tier \"ultrafast\"";

fn fallback_client(runner: Runner, output_mode: OutputMode) -> (Client, Request) {
    let mut config = CccConfig::default();
    config.aliases.insert(
        "reviewer".into(),
        AliasDef {
            runner: Some("codex".into()),
            model: Some(PRIMARY.into()),
            agent: Some("unauthorized".into()),
            fallback_models: Some(vec![
                "gpt-6-luna".into(),
                "glm-5.3".into(),
                FINAL_MODEL.into(),
            ]),
            ..AliasDef::default()
        },
    );
    let request = Request::new("hello")
        .with_agent("reviewer")
        .with_service_tier("ultrafast")
        .with_save_session(true)
        .with_output_mode(output_mode);
    (
        Client::new()
            .with_config(config)
            .with_runtime_runner(runner),
        request,
    )
}

fn attempt_result(spec: CommandSpec, final_exit_code: i32) -> CompletedRun {
    let model_at = spec.argv.iter().position(|arg| arg == "--model").unwrap();
    let model = &spec.argv[model_at + 1];
    let expected_runner = if model.starts_with("glm-") {
        "grok"
    } else {
        "codex"
    };
    assert_eq!(spec.argv[0], expected_runner);
    if model == FINAL_MODEL {
        CompletedRun::new(
            spec.argv,
            final_exit_code,
            if final_exit_code == 0 { "done\n" } else { "" },
            "final runner stderr\n",
        )
    } else {
        let stderr = format!("{model}: server_overloaded\n");
        CompletedRun::new(spec.argv, 1, "", stderr)
    }
}

fn assert_fallback_warnings(run: &Run, initial_warnings: &[String], final_exit_code: i32) {
    assert!(!initial_warnings.is_empty());
    for warning in initial_warnings {
        assert!(
            !run.stderr().contains(warning),
            "replayed initial warning: {warning}"
        );
    }
    assert_eq!(run.stderr().matches(TIER_WARNING).count(), 1);
    assert!(run
        .plan()
        .warnings()
        .iter()
        .any(|item| item == TIER_WARNING));
    assert_eq!(run.plan().runner(), RunnerKind::Grok);
    assert_eq!(run.exit_code(), final_exit_code);
    assert_eq!(run.stderr().matches("final runner stderr\n").count(), 1);
    for model in [PRIMARY, "gpt-6-luna", "glm-5.3"] {
        assert_eq!(
            run.stderr()
                .matches(&format!("{model}: server_overloaded\n"))
                .count(),
            1
        );
    }
    let tier_at = run.stderr().find(TIER_WARNING).unwrap();
    let grok_stderr_at = run.stderr().find("glm-5.3: server_overloaded").unwrap();
    assert!(tier_at < grok_stderr_at);
    if final_exit_code == 0 {
        assert_eq!(run.stdout(), "done\n");
        assert!(run
            .stderr()
            .ends_with(&format!("ccc: ran model {FINAL_MODEL}\n")));
    } else {
        assert_eq!(run.stdout(), "");
        assert!(run.stderr().ends_with(&format!(
            "ccc: model {FINAL_MODEL} failed; not falling back\n"
        )));
    }
}

#[test]
fn buffered_fallback_warnings_are_new_and_emitted_once() {
    for final_exit_code in [0, 7] {
        let runner =
            Runner::with_executor(Box::new(move |spec| attempt_result(spec, final_exit_code)));
        let (client, request) = fallback_client(runner, OutputMode::Text);
        let initial = client.plan(&request).unwrap();
        let run = client.run_unchecked(&request).unwrap();
        assert_fallback_warnings(&run, initial.warnings(), final_exit_code);
    }
}

#[test]
fn streamed_fallback_warnings_are_new_and_emitted_once() {
    for final_exit_code in [0, 7] {
        let events = Arc::new(Mutex::new(Vec::<(String, String)>::new()));
        let events_for_callback = Arc::clone(&events);
        let runner = Runner::with_stream_executor(Box::new(move |spec, callback| {
            let completed = attempt_result(spec, final_exit_code);
            let mut callback = callback.lock().unwrap();
            if !completed.stdout.is_empty() {
                callback("stdout", &completed.stdout);
            }
            callback("stderr", &completed.stderr);
            completed
        }));
        let (client, request) = fallback_client(runner, OutputMode::StreamText);
        let initial = client.plan(&request).unwrap();
        let mut runners = Vec::new();
        let run = client
            .stream_unchecked_with_attempt(
                &request,
                |runner| runners.push(runner.to_string()),
                move |channel, chunk| {
                    events_for_callback
                        .lock()
                        .unwrap()
                        .push((channel.into(), chunk.into()));
                },
            )
            .unwrap();
        assert_fallback_warnings(&run, initial.warnings(), final_exit_code);
        assert_eq!(runners, ["codex", "codex", "grok", "grok"]);
        let events = events.lock().unwrap();
        let stderr: String = events
            .iter()
            .filter(|(channel, _)| channel == "stderr")
            .map(|(_, chunk)| chunk.as_str())
            .collect();
        let stdout: String = events
            .iter()
            .filter(|(channel, _)| channel == "stdout")
            .map(|(_, chunk)| chunk.as_str())
            .collect();
        assert_eq!(stderr, run.stderr());
        assert_eq!(stdout, run.stdout());
    }
}

use call_coding_clis::{build_prompt_spec, CommandSpec, CompletedRun, Runner};
use std::path::Path;
use std::sync::{Arc, Mutex};

#[test]
fn run_returns_completed_result() {
    let runner = Runner::with_executor(Box::new(|spec| CompletedRun {
        argv: spec.argv,
        exit_code: 0,
        stdout: "ok".to_owned(),
        stderr: String::new(),
    }));

    let result = runner.run(CommandSpec::new(["fake", "--json"]));

    assert_eq!(result.argv, vec!["fake", "--json"]);
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "ok");
    assert_eq!(result.stderr, "");
}

#[test]
fn run_reports_missing_binary_start_failure() {
    let result = Runner::new().run(CommandSpec::new(["/definitely/missing/runner-binary"]));

    assert_ne!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert!(result.stderr.contains("failed to start"));
    assert!(result.stderr.contains("runner-binary"));
}

#[test]
fn stream_emits_events_and_exit_code() {
    let runner = Runner::with_stream_executor(Box::new(|spec, callback| {
        if let Ok(mut cb) = callback.lock() {
            cb("stdout", "hello");
            cb("stderr", "warn");
        }
        CompletedRun {
            argv: spec.argv,
            exit_code: 2,
            stdout: String::new(),
            stderr: String::new(),
        }
    }));

    let events: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
    let events_clone = Arc::clone(&events);
    let result = runner.stream(CommandSpec::new(["fake"]), move |channel, chunk| {
        events_clone
            .lock()
            .unwrap()
            .push((channel.to_owned(), chunk.to_owned()));
    });

    let events = events.lock().unwrap();
    assert_eq!(
        *events,
        vec![
            ("stdout".to_owned(), "hello".to_owned()),
            ("stderr".to_owned(), "warn".to_owned())
        ]
    );
    assert_eq!(result.exit_code, 2);
}

#[test]
fn stream_reports_missing_binary_start_failure_as_stderr_event() {
    let events: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
    let events_clone = Arc::clone(&events);
    let result = Runner::new().stream(
        CommandSpec::new(["/definitely/missing/runner-binary"]),
        move |channel, chunk| {
            events_clone
                .lock()
                .unwrap()
                .push((channel.to_owned(), chunk.to_owned()));
        },
    );

    let events = events.lock().unwrap();
    assert_ne!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert!(result.stderr.contains("failed to start"));
    assert!(result.stderr.contains("runner-binary"));
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].0, "stderr");
    assert!(events[0].1.contains("failed to start"));
}

#[test]
fn command_spec_preserves_cwd_stdin_and_env() {
    let spec = CommandSpec::new(["fake"])
        .with_stdin("hello")
        .with_cwd("/tmp/work")
        .with_env("MODEL", "glm-5.1");

    assert_eq!(spec.stdin_text.as_deref(), Some("hello"));
    assert_eq!(spec.cwd.as_deref(), Some(Path::new("/tmp/work")));
    assert_eq!(spec.env.get("MODEL").map(String::as_str), Some("glm-5.1"));
}

#[test]
fn ccc_builds_prompt_command_spec() {
    let spec = build_prompt_spec("Fix the failing tests").expect("prompt should be valid");

    assert_eq!(spec.argv, vec!["opencode", "run", "Fix the failing tests"]);
}

#[test]
fn ccc_rejects_empty_prompt() {
    assert!(build_prompt_spec("   ").is_err());
}

use call_coding_clis::{CommandSpec, CompletedRun, Runner};
use std::path::Path;

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
fn stream_emits_events_and_exit_code() {
    let runner = Runner::with_stream_executor(Box::new(|spec, mut callback| {
        callback("stdout", "hello");
        callback("stderr", "warn");
        CompletedRun {
            argv: spec.argv,
            exit_code: 2,
            stdout: String::new(),
            stderr: String::new(),
        }
    }));

    let mut events = Vec::new();
    let result = runner.stream(CommandSpec::new(["fake"]), |channel, chunk| {
        events.push((channel.to_owned(), chunk.to_owned()));
    });

    assert_eq!(
        events,
        vec![
            ("stdout".to_owned(), "hello".to_owned()),
            ("stderr".to_owned(), "warn".to_owned())
        ]
    );
    assert_eq!(result.exit_code, 2);
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

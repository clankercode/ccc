use call_coding_clis::{
    output_write_warning, parse_args, resolve_state_root, FormattedRenderer, RunArtifacts,
    StructuredStreamProcessor, TranscriptKind,
};
use std::env;
use std::fs::{self, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static ENV_LOCK: Mutex<()> = Mutex::new(());

fn ccc_bin() -> &'static str {
    env!("CARGO_BIN_EXE_ccc")
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("rust crate has repo parent")
        .to_path_buf()
}

fn mock_runner() -> PathBuf {
    repo_root().join("tests/mock-coding-cli/mock_coding_cli.sh")
}

fn unique_dir(prefix: &str) -> PathBuf {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock moved backwards")
        .as_nanos();
    env::temp_dir().join(format!("ccc-rust-{prefix}-{}-{stamp}", std::process::id()))
}

fn transcript_entries(run_dir: &Path) -> Vec<PathBuf> {
    fs::read_dir(run_dir)
        .unwrap()
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.file_name()
                .and_then(|value| value.to_str())
                .is_some_and(|name| name.starts_with("transcript."))
        })
        .collect()
}

fn assert_run_dir_prefix(run_dir: &Path, prefix: &str) {
    let run_name = run_dir
        .file_name()
        .and_then(|value| value.to_str())
        .expect("run dir should have a valid name");
    assert!(
        run_name.starts_with(prefix),
        "expected {run_name} to start with {prefix}"
    );
}

#[test]
fn parse_args_supports_output_log_flags_last_wins() {
    let parsed = parse_args(&[
        "--no-output-log-path".into(),
        "--output-log-path".into(),
        "hello".into(),
    ]);
    assert_eq!(parsed.output_log_path, Some(true));

    let parsed = parse_args(&[
        "--output-log-path".into(),
        "--no-output-log-path".into(),
        "hello".into(),
    ]);
    assert_eq!(parsed.output_log_path, Some(false));
}

#[test]
fn resolve_state_root_prefers_xdg_state_home_then_home_fallback() {
    let _guard = ENV_LOCK.lock().unwrap();
    let base = unique_dir("state-root");
    let xdg_state_home = base.join("xdg-state");
    let home = base.join("home");
    fs::create_dir_all(&xdg_state_home).unwrap();
    fs::create_dir_all(&home).unwrap();

    let old_xdg_state_home = env::var_os("XDG_STATE_HOME");
    let old_home = env::var_os("HOME");
    env::set_var("XDG_STATE_HOME", &xdg_state_home);
    env::set_var("HOME", &home);

    assert_eq!(resolve_state_root(), xdg_state_home);

    env::remove_var("XDG_STATE_HOME");

    let resolved = resolve_state_root();
    if cfg!(target_os = "macos") {
        assert_eq!(resolved, home.join("Library/Application Support"));
    } else if cfg!(target_os = "windows") {
        assert_eq!(resolved, home.join("AppData/Local"));
    } else {
        assert_eq!(resolved, home.join(".local/state"));
    }

    match old_xdg_state_home {
        Some(value) => env::set_var("XDG_STATE_HOME", value),
        None => env::remove_var("XDG_STATE_HOME"),
    }
    match old_home {
        Some(value) => env::set_var("HOME", value),
        None => env::remove_var("HOME"),
    }
}

#[test]
fn run_artifacts_retry_existing_run_dir_candidate() {
    let root = unique_dir("run-dir-retry");
    let state_root = root.join("state");
    let runs_root = state_root.join("ccc/runs");
    fs::create_dir_all(&runs_root).unwrap();

    let first_candidate = "20260415-1234-0";
    let second_candidate = "20260415-1234-1";
    fs::create_dir_all(runs_root.join(first_candidate)).unwrap();

    let mut candidates =
        vec![first_candidate.to_string(), second_candidate.to_string()].into_iter();
    let artifacts =
        RunArtifacts::create_in_with_id_source(&state_root, TranscriptKind::Text, move || {
            candidates.next().expect("expected a retry candidate")
        })
        .expect("run artifacts should retry candidate directories");

    assert_eq!(artifacts.run_dir(), runs_root.join(second_candidate));
    assert!(artifacts.run_dir().is_dir());
    assert_eq!(
        artifacts.transcript_path(),
        artifacts.run_dir().join("transcript.txt")
    );
}

#[test]
fn run_artifacts_prefixes_run_dir_with_canonical_client_name() {
    let root = unique_dir("run-dir-prefix");
    let state_root = root.join("state");
    let runs_root = state_root.join("ccc/runs");

    let artifacts = RunArtifacts::create_in_with_id_source_for_runner(
        &state_root,
        TranscriptKind::Text,
        "g",
        || "run-1".to_string(),
    )
    .expect("run artifacts should prefix runner directories");

    assert_eq!(artifacts.run_dir(), runs_root.join("gemini-run-1"));
    assert!(artifacts.run_dir().is_dir());
}

#[test]
fn run_artifacts_write_expected_files_and_footer() {
    let root = unique_dir("run-artifacts-write");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in(&state_root, TranscriptKind::Text)
        .expect("run artifacts should be created");

    artifacts.record_stdout("hello\n").unwrap();
    artifacts.record_stdout("world").unwrap();
    artifacts.write_output_text("final message").unwrap();

    assert_eq!(
        fs::read_to_string(artifacts.output_path()).unwrap(),
        "final message"
    );
    assert_eq!(
        fs::read_to_string(artifacts.transcript_path()).unwrap(),
        "hello\nworld"
    );
    assert_eq!(
        artifacts.footer_line(),
        format!(">> ccc:output-log >> {}", artifacts.run_dir().display())
    );
}

#[test]
fn run_artifacts_use_jsonl_transcript_for_json_modes() {
    let root = unique_dir("run-artifacts-jsonl");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in(&state_root, TranscriptKind::Jsonl)
        .expect("run artifacts should be created");

    artifacts
        .record_stdout("{\"response\":\"hello\"}\n")
        .unwrap();
    assert!(artifacts.transcript_path().ends_with("transcript.jsonl"));
    assert_eq!(
        fs::read_to_string(artifacts.transcript_path()).unwrap(),
        "{\"response\":\"hello\"}\n"
    );
}

#[test]
fn run_artifacts_write_output_reports_post_directory_failure() {
    let root = unique_dir("run-artifacts-output-fail");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in(&state_root, TranscriptKind::Text)
        .expect("run artifacts should be created");

    fs::create_dir_all(artifacts.output_path()).unwrap();
    let error = artifacts
        .write_output_text("final message")
        .expect_err("writing output should fail when the path is a directory");
    assert_eq!(error.kind(), std::io::ErrorKind::IsADirectory);
    assert!(output_write_warning(&error).starts_with("warning: could not write output.txt: "));
    assert_eq!(
        artifacts.footer_line(),
        format!(">> ccc:output-log >> {}", artifacts.run_dir().display())
    );
}

#[test]
fn run_artifacts_warn_when_transcript_open_fails() {
    let root = unique_dir("run-artifacts-transcript-open-fail");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in_with_id_source_and_transcript_opener(
        &state_root,
        TranscriptKind::Text,
        || "run-1".to_string(),
        |_path| {
            Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "permission denied",
            ))
        },
    )
    .expect("run artifacts should still create the run directory");

    let warning = artifacts
        .transcript_warning()
        .expect("transcript open failure should be visible");
    assert!(warning.starts_with("warning: could not create transcript.txt: "));
    assert!(warning.contains("permission denied"));
}

#[test]
fn run_artifacts_reports_transcript_creation_warning() {
    let root = unique_dir("run-artifacts-transcript-create-fail");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in_with_id_source_and_transcript_opener(
        &state_root,
        TranscriptKind::Text,
        || "run-1".to_string(),
        |_path| {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "denied",
            ))
        },
    )
    .expect("run artifacts should still create the run directory");

    assert_eq!(
        artifacts.transcript_warning(),
        Some("warning: could not create transcript.txt: denied")
    );
    assert!(artifacts.record_stdout("hello").is_ok());
    assert!(!artifacts.transcript_path().exists());
}

#[cfg(unix)]
#[test]
fn run_artifacts_reports_transcript_write_failure() {
    let root = unique_dir("run-artifacts-transcript-write-fail");
    let state_root = root.join("state");
    let artifacts = RunArtifacts::create_in_with_id_source_and_transcript_opener(
        &state_root,
        TranscriptKind::Text,
        || "run-1".to_string(),
        |_path| OpenOptions::new().write(true).open("/dev/full"),
    )
    .expect("run artifacts should still create the run directory");

    let error = artifacts
        .record_stdout("hello")
        .expect_err("writing to /dev/full should fail");
    assert!(
        matches!(
            error.kind(),
            std::io::ErrorKind::WriteZero
                | std::io::ErrorKind::StorageFull
                | std::io::ErrorKind::Other
        ),
        "{error:?}"
    );
    assert!(artifacts.record_stdout("again").is_ok());
}

#[test]
fn structured_stream_processor_exposes_final_text_after_finish() {
    let mut processor =
        StructuredStreamProcessor::new("opencode", FormattedRenderer::new(true, false));
    let rendered = processor.feed("{\"response\":\"hello\"}\n");
    assert_eq!(rendered, "[assistant] hello");
    assert_eq!(processor.output().final_text, "hello");
    assert!(processor.finish().is_empty());
    assert_eq!(processor.output().final_text, "hello");
}

#[test]
fn ccc_stream_formatted_smoke_writes_rendered_transcript_and_footer() {
    let _guard = ENV_LOCK.lock().unwrap();
    let sandbox = unique_dir("stream-formatted-smoke");
    let state_home = sandbox.join("state");
    let home = sandbox.join("home");
    fs::create_dir_all(&state_home).unwrap();
    fs::create_dir_all(&home).unwrap();

    let output = Command::new(ccc_bin())
        .current_dir(&sandbox)
        .args(["oc", "..fmt", "tool call"])
        .env("CCC_REAL_OPENCODE", mock_runner())
        .env("MOCK_JSON_SCHEMA", "opencode")
        .env("XDG_STATE_HOME", &state_home)
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", sandbox.join("config"))
        .env("CCC_CONFIG", sandbox.join("missing.toml"))
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let footer_line = stderr
        .lines()
        .last()
        .expect("stderr should contain a footer");
    assert!(footer_line.starts_with(">> ccc:output-log >> "));

    let run_dir = PathBuf::from(footer_line.trim_start_matches(">> ccc:output-log >> "));
    assert!(run_dir.is_dir());
    assert_run_dir_prefix(&run_dir, "opencode-");
    assert!(run_dir.join("output.txt").is_file());
    assert_eq!(
        transcript_entries(&run_dir),
        vec![run_dir.join("transcript.txt")]
    );
    assert_eq!(
        fs::read_to_string(run_dir.join("output.txt")).unwrap(),
        "mock: tool call executed"
    );
    let transcript = fs::read_to_string(run_dir.join("transcript.txt")).unwrap();
    assert!(transcript.contains("[tool:start] read"));
    assert!(transcript.contains("[tool:result] read (ok)"));
    assert!(transcript.contains("[assistant] mock: tool call executed"));
}

#[test]
fn ccc_text_upgrade_path_still_uses_transcript_txt() {
    let _guard = ENV_LOCK.lock().unwrap();
    let sandbox = unique_dir("text-upgrade-smoke");
    let state_home = sandbox.join("state");
    let home = sandbox.join("home");
    fs::create_dir_all(&state_home).unwrap();
    fs::create_dir_all(&home).unwrap();

    let output = Command::new(ccc_bin())
        .current_dir(&sandbox)
        .args(["oc", "--show-thinking", "tool call"])
        .env("CCC_REAL_OPENCODE", mock_runner())
        .env("MOCK_JSON_SCHEMA", "opencode")
        .env("XDG_STATE_HOME", &state_home)
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", sandbox.join("config"))
        .env("CCC_CONFIG", sandbox.join("missing.toml"))
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let footer_line = stderr
        .lines()
        .last()
        .expect("stderr should contain a footer");
    assert!(footer_line.starts_with(">> ccc:output-log >> "));

    let run_dir = PathBuf::from(footer_line.trim_start_matches(">> ccc:output-log >> "));
    assert_run_dir_prefix(&run_dir, "opencode-");
    assert!(run_dir.join("output.txt").is_file());
    assert_eq!(
        transcript_entries(&run_dir),
        vec![run_dir.join("transcript.txt")]
    );
    let transcript = fs::read_to_string(run_dir.join("transcript.txt")).unwrap();
    assert!(transcript.contains("[assistant] mock: tool call executed"));
}

#[test]
fn ccc_no_output_log_path_suppresses_footer_but_keeps_artifacts() {
    let _guard = ENV_LOCK.lock().unwrap();
    let sandbox = unique_dir("footer-suppression-smoke");
    let state_home = sandbox.join("state");
    let home = sandbox.join("home");
    fs::create_dir_all(&state_home).unwrap();
    fs::create_dir_all(&home).unwrap();

    let output = Command::new(ccc_bin())
        .current_dir(&sandbox)
        .args(["oc", "--show-thinking", "--no-output-log-path", "tool call"])
        .env("CCC_REAL_OPENCODE", mock_runner())
        .env("MOCK_JSON_SCHEMA", "opencode")
        .env("XDG_STATE_HOME", &state_home)
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", sandbox.join("config"))
        .env("CCC_CONFIG", sandbox.join("missing.toml"))
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stderr.contains(">> ccc:output-log >> "));

    let runs_root = state_home.join("ccc/runs");
    let runs: Vec<_> = fs::read_dir(&runs_root).unwrap().collect();
    assert_eq!(runs.len(), 1);
    let run_dir = runs[0].as_ref().unwrap().path();
    assert_run_dir_prefix(&run_dir, "opencode-");
    assert!(run_dir.join("output.txt").is_file());
    assert_eq!(
        transcript_entries(&run_dir),
        vec![run_dir.join("transcript.txt")]
    );
}

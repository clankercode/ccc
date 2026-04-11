use call_coding_clis::{
    find_config_command_path, load_config, parse_args, parse_json_output, print_help, print_usage,
    render_example_config, render_parsed, resolve_command, resolve_human_tty, resolve_output_plan,
    resolve_sanitize_osc, resolve_show_thinking, FormattedRenderer, Runner,
    StructuredStreamProcessor,
};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::sync::{Arc, Mutex};

fn filtered_human_stderr(stderr: &str, runner_name: &str) -> String {
    if !matches!(runner_name, "k" | "kimi") || stderr.is_empty() {
        return stderr.to_string();
    }
    let kept = stderr
        .lines()
        .filter(|line| {
            let trimmed = line.trim();
            !trimmed.is_empty() && !trimmed.starts_with("To resume this session: kimi -r ")
        })
        .collect::<Vec<_>>();
    if kept.is_empty() {
        String::new()
    } else {
        format!("{}\n", kept.join("\n"))
    }
}

fn sanitize_raw_output(text: &str, runner_name: &str) -> String {
    if !matches!(runner_name, "oc" | "opencode") || text.is_empty() {
        return text.to_string();
    }
    let mut output = String::new();
    let mut remaining = text;
    while let Some(start) = remaining.find("\u{1b}]") {
        output.push_str(&remaining[..start]);
        let osc = &remaining[start + 2..];
        if let Some(end) = osc.find('\u{7}') {
            remaining = &osc[end + 1..];
            continue;
        }
        if let Some(end) = osc.find("\u{1b}\\") {
            remaining = &osc[end + 2..];
            continue;
        }
        remaining = "";
        break;
    }
    output.push_str(remaining);
    output
}

fn sanitize_human_output(text: &str, sanitize_osc: bool) -> String {
    if !sanitize_osc || text.is_empty() {
        return text.to_string();
    }
    let mut output = String::new();
    let mut preserved = Vec::new();
    let mut remaining = text;
    while let Some(start) = remaining.find("\u{1b}]") {
        output.push_str(&remaining[..start]);
        let osc = &remaining[start..];
        let end = if let Some(index) = osc[2..].find('\u{7}') {
            Some(start + 2 + index + 1)
        } else if let Some(index) = osc[2..].find("\u{1b}\\") {
            Some(start + 2 + index + 2)
        } else {
            None
        };
        let Some(end) = end else {
            remaining = &remaining[..start];
            break;
        };
        let full = &remaining[start..end];
        if full.starts_with("\u{1b}]8;") {
            let marker = format!("\0OSC8{}\0", preserved.len());
            preserved.push(full.to_string());
            output.push_str(&marker);
        }
        remaining = &remaining[end..];
    }
    output.push_str(remaining);
    let mut sanitized: String = output.chars().filter(|ch| *ch != '\u{7}').collect();
    for (index, value) in preserved.iter().enumerate() {
        let marker = format!("\0OSC8{}\0", index);
        sanitized = sanitized.replace(&marker, value);
    }
    sanitized
}

fn print_cleanup_warnings(
    cleanup_session: bool,
    runner_name: &str,
    spec: &call_coding_clis::CommandSpec,
    result: &call_coding_clis::CompletedRun,
) {
    if !cleanup_session {
        return;
    }
    let runner_binary = spec.argv.first().map(String::as_str).unwrap_or(runner_name);
    for warning in cleanup_runner_session(
        runner_name,
        runner_binary,
        &result.stdout,
        &result.stderr,
        &spec.env,
    ) {
        eprintln!("{warning}");
    }
}

fn session_persistence_pre_run_warnings(
    save_session: bool,
    cleanup_session: bool,
    runner_name: &str,
) -> Vec<String> {
    if save_session || cleanup_session {
        return Vec::new();
    }
    let display = canonical_session_runner_name(runner_name);
    if !matches!(display.as_str(), "opencode" | "kimi" | "crush" | "roocode") {
        return Vec::new();
    }
    vec![format!(
        "warning: runner \"{display}\" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup"
    )]
}

fn canonical_session_runner_name(runner_name: &str) -> String {
    match runner_name {
        "oc" | "opencode" => "opencode".to_string(),
        "k" | "kimi" => "kimi".to_string(),
        "cr" | "crush" => "crush".to_string(),
        "rc" | "roocode" => "roocode".to_string(),
        _ => runner_name.to_string(),
    }
}

fn extract_opencode_session_id(stdout: &str) -> Option<String> {
    for line in stdout.lines() {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let Some(session_id) = value.get("sessionID").and_then(|value| value.as_str()) else {
            continue;
        };
        if !session_id.is_empty() {
            return Some(session_id.to_string());
        }
    }
    None
}

fn extract_kimi_resume_session_id(stderr: &str) -> Option<String> {
    let marker = "To resume this session: kimi -r ";
    let start = stderr.find(marker)? + marker.len();
    let id = stderr[start..]
        .chars()
        .take_while(|ch| ch.is_ascii_hexdigit() || *ch == '-')
        .collect::<String>();
    if id.is_empty() {
        None
    } else {
        Some(id)
    }
}

fn cleanup_runner_session(
    runner_name: &str,
    runner_binary: &str,
    stdout: &str,
    stderr: &str,
    env_overrides: &BTreeMap<String, String>,
) -> Vec<String> {
    match runner_name {
        "oc" | "opencode" => cleanup_opencode_session(runner_binary, stdout),
        "k" | "kimi" => cleanup_kimi_session(stderr, env_overrides),
        _ => Vec::new(),
    }
}

fn cleanup_opencode_session(runner_binary: &str, stdout: &str) -> Vec<String> {
    let Some(session_id) = extract_opencode_session_id(stdout) else {
        return vec!["warning: could not find OpenCode session ID for cleanup".to_string()];
    };
    match Command::new(runner_binary)
        .args(["session", "delete", &session_id])
        .output()
    {
        Ok(output) if output.status.success() => Vec::new(),
        Ok(output) => {
            let detail = String::from_utf8_lossy(if output.stderr.is_empty() {
                &output.stdout
            } else {
                &output.stderr
            })
            .trim()
            .to_string();
            if detail.is_empty() {
                vec![format!(
                    "warning: failed to cleanup OpenCode session {session_id}"
                )]
            } else {
                vec![format!(
                    "warning: failed to cleanup OpenCode session {session_id}: {detail}"
                )]
            }
        }
        Err(error) => vec![format!(
            "warning: failed to cleanup OpenCode session {session_id}: {error}"
        )],
    }
}

fn cleanup_kimi_session(stderr: &str, env_overrides: &BTreeMap<String, String>) -> Vec<String> {
    let Some(session_id) = extract_kimi_resume_session_id(stderr) else {
        return vec!["warning: could not find Kimi session ID for cleanup".to_string()];
    };
    let root = env_overrides
        .get("KIMI_SHARE_DIR")
        .cloned()
        .or_else(|| env::var("KIMI_SHARE_DIR").ok())
        .or_else(|| env::var("HOME").ok().map(|home| format!("{home}/.kimi")))
        .map(PathBuf::from);
    let Some(root) = root else {
        return vec![format!(
            "warning: could not find Kimi session file for cleanup: {session_id}"
        )];
    };
    let mut matches = Vec::new();
    collect_kimi_session_files(&root.join("sessions"), &session_id, &mut matches);
    if matches.is_empty() {
        return vec![format!(
            "warning: could not find Kimi session file for cleanup: {session_id}"
        )];
    }
    let mut warnings = Vec::new();
    for path in matches {
        let result = if path.is_dir() {
            fs::remove_dir_all(&path)
        } else {
            fs::remove_file(&path)
        };
        if let Err(error) = result {
            warnings.push(format!(
                "warning: failed to cleanup Kimi session {session_id}: {error}"
            ));
        }
    }
    warnings
}

fn collect_kimi_session_files(dir: &Path, session_id: &str, matches: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.starts_with(session_id))
            .unwrap_or(false)
        {
            matches.push(path);
            continue;
        }
        if path.is_dir() {
            collect_kimi_session_files(&path, session_id, matches);
        }
    }
}

fn apply_real_runner_override(spec: &mut call_coding_clis::CommandSpec) {
    if spec.argv.is_empty() {
        return;
    }
    let env_var = match spec.argv[0].as_str() {
        "opencode" => Some("CCC_REAL_OPENCODE"),
        "claude" => Some("CCC_REAL_CLAUDE"),
        "kimi" => Some("CCC_REAL_KIMI"),
        _ => None,
    };
    if let Some(env_var) = env_var {
        if let Ok(override_binary) = env::var(env_var) {
            if !override_binary.is_empty() {
                spec.argv[0] = override_binary;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        apply_real_runner_override, cleanup_runner_session, extract_kimi_resume_session_id,
        extract_opencode_session_id, filtered_human_stderr, sanitize_human_output,
        sanitize_raw_output, session_persistence_pre_run_warnings,
    };
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::PathBuf;

    #[test]
    fn strips_kimi_resume_hint() {
        let stderr = "\nTo resume this session: kimi -r 123e4567-e89b-12d3-a456-426614174000\n";
        assert_eq!(filtered_human_stderr(stderr, "k"), "");
    }

    #[test]
    fn keeps_other_stderr() {
        let stderr = "warning: something else\n";
        assert_eq!(filtered_human_stderr(stderr, "cc"), stderr);
    }

    #[test]
    fn extracts_opencode_session_id_from_step_start() {
        let stdout = "{\"type\":\"step_start\",\"sessionID\":\"ses_123\"}\n{\"type\":\"text\"}\n";
        assert_eq!(
            extract_opencode_session_id(stdout),
            Some("ses_123".to_string())
        );
    }

    #[test]
    fn extracts_kimi_resume_session_id_from_stderr() {
        let stderr = "To resume this session: kimi -r 123e4567-e89b-12d3-a456-426614174000\n";
        assert_eq!(
            extract_kimi_resume_session_id(stderr),
            Some("123e4567-e89b-12d3-a456-426614174000".to_string())
        );
    }

    #[test]
    fn cleanup_runner_session_deletes_kimi_session_file_from_share_dir() {
        let tmp = unique_tmp_dir("kimi-cleanup");
        let session_id = "123e4567-e89b-12d3-a456-426614174000";
        let session_file = tmp
            .join("sessions")
            .join("2026")
            .join(format!("{session_id}.json"));
        fs::create_dir_all(session_file.parent().unwrap()).unwrap();
        fs::write(&session_file, "{}").unwrap();

        let mut env = BTreeMap::new();
        env.insert(
            "KIMI_SHARE_DIR".to_string(),
            tmp.to_string_lossy().into_owned(),
        );
        let warnings = cleanup_runner_session(
            "k",
            "kimi",
            "",
            &format!("To resume this session: kimi -r {session_id}\n"),
            &env,
        );

        assert!(!session_file.exists());
        assert!(warnings.is_empty());
        let _ = fs::remove_dir_all(tmp);
    }

    #[test]
    fn cleanup_runner_session_deletes_kimi_session_directory_from_share_dir() {
        let tmp = unique_tmp_dir("kimi-cleanup-dir");
        let session_id = "123e4567-e89b-12d3-a456-426614174000";
        let session_dir = tmp.join("sessions").join("workdir-hash").join(session_id);
        fs::create_dir_all(&session_dir).unwrap();
        fs::write(session_dir.join("session.json"), "{}").unwrap();

        let mut env = BTreeMap::new();
        env.insert(
            "KIMI_SHARE_DIR".to_string(),
            tmp.to_string_lossy().into_owned(),
        );
        let warnings = cleanup_runner_session(
            "k",
            "kimi",
            "",
            &format!("To resume this session: kimi -r {session_id}\n"),
            &env,
        );

        assert!(!session_dir.exists());
        assert!(warnings.is_empty());
        let _ = fs::remove_dir_all(tmp);
    }

    #[test]
    fn cleanup_runner_session_warns_when_opencode_session_id_is_missing() {
        let warnings = cleanup_runner_session(
            "oc",
            "opencode",
            "{\"type\":\"text\"}\n",
            "",
            &BTreeMap::new(),
        );
        assert_eq!(
            warnings,
            vec!["warning: could not find OpenCode session ID for cleanup".to_string()]
        );
    }

    #[test]
    fn session_persistence_pre_run_warning_policy() {
        assert_eq!(
            session_persistence_pre_run_warnings(false, false, "oc"),
            vec!["warning: runner \"opencode\" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup".to_string()]
        );
        assert!(session_persistence_pre_run_warnings(true, false, "oc").is_empty());
        assert!(session_persistence_pre_run_warnings(false, true, "oc").is_empty());
        assert!(session_persistence_pre_run_warnings(false, false, "cc").is_empty());
    }

    fn unique_tmp_dir(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "ccc-{name}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn strips_opencode_osc_from_raw_output() {
        let stdout = concat!(
            "{\"type\":\"text\",\"part\":{\"text\":\"alpha\"}}\n",
            "\u{1b}]9;OC | call-coding-clis: Agent finished: alpha\u{7}"
        );
        assert_eq!(
            sanitize_raw_output(stdout, "oc"),
            "{\"type\":\"text\",\"part\":{\"text\":\"alpha\"}}\n"
        );
    }

    #[test]
    fn keeps_other_runner_raw_output() {
        let stdout = "plain output\n";
        assert_eq!(sanitize_raw_output(stdout, "cc"), stdout);
    }

    #[test]
    fn sanitize_human_output_strips_title_and_bell() {
        let text = "hello\u{1b}]9;title here\u{7}world\u{7}!\n";
        assert_eq!(sanitize_human_output(text, true), "helloworld!\n");
    }

    #[test]
    fn sanitize_human_output_preserves_osc8_hyperlink() {
        let text = "\u{1b}]8;;https://example.com\u{7}click\u{1b}]8;;\u{7}";
        assert_eq!(sanitize_human_output(text, true), text);
    }

    #[test]
    fn sanitize_human_output_can_be_disabled() {
        let text = "hello\u{1b}]9;title here\u{7}world\u{7}!\n";
        assert_eq!(sanitize_human_output(text, false), text);
    }

    #[test]
    fn apply_real_runner_override_for_claude() {
        let key = "CCC_REAL_CLAUDE";
        let original = std::env::var(key).ok();
        unsafe { std::env::set_var(key, "/tmp/mock-claude") };
        let mut spec = call_coding_clis::CommandSpec::new(["claude", "-p", "hello"]);
        apply_real_runner_override(&mut spec);
        assert_eq!(spec.argv[0], "/tmp/mock-claude");
        if let Some(value) = original {
            unsafe { std::env::set_var(key, value) };
        } else {
            unsafe { std::env::remove_var(key) };
        }
    }

    #[test]
    fn apply_real_runner_override_for_kimi() {
        let key = "CCC_REAL_KIMI";
        let original = std::env::var(key).ok();
        unsafe { std::env::set_var(key, "/tmp/mock-kimi") };
        let mut spec = call_coding_clis::CommandSpec::new(["kimi", "--prompt", "hello"]);
        apply_real_runner_override(&mut spec);
        assert_eq!(spec.argv[0], "/tmp/mock-kimi");
        if let Some(value) = original {
            unsafe { std::env::set_var(key, value) };
        } else {
            unsafe { std::env::remove_var(key) };
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    if args.is_empty() {
        print_usage();
        return ExitCode::from(1);
    }

    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_help();
        return ExitCode::from(0);
    }

    if args == ["config"] {
        let Some(config_path) = find_config_command_path() else {
            if let Ok(explicit) = env::var("CCC_CONFIG") {
                let trimmed = explicit.trim();
                if !trimmed.is_empty() {
                    eprintln!("No config file found at {trimmed}");
                } else {
                    eprintln!(
                        "No config file found in .ccc.toml, XDG_CONFIG_HOME/ccc/config.toml, or ~/.config/ccc/config.toml"
                    );
                }
            } else {
                eprintln!(
                    "No config file found in .ccc.toml, XDG_CONFIG_HOME/ccc/config.toml, or ~/.config/ccc/config.toml"
                );
            }
            return ExitCode::from(1);
        };
        let content = match std::fs::read_to_string(&config_path) {
            Ok(content) => content,
            Err(error) => {
                eprintln!(
                    "Failed to read config file {}: {error}",
                    config_path.display()
                );
                return ExitCode::from(1);
            }
        };
        println!("Config path: {}", config_path.display());
        print!("{content}");
        return ExitCode::from(0);
    }

    let parsed = parse_args(&args);
    if parsed.print_config {
        if args != ["--print-config"] {
            eprintln!("--print-config must be used on its own");
            return ExitCode::from(1);
        }
        print!("{}", render_example_config());
        return ExitCode::from(0);
    }

    let config = load_config(None);
    let output_plan = match resolve_output_plan(&parsed, Some(&config)) {
        Ok(plan) => plan,
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(1);
        }
    };
    let spec = match resolve_command(&parsed, Some(&config)) {
        Ok((argv, env_overrides, warnings)) => {
            let mut spec = call_coding_clis::CommandSpec::new(argv);
            for (k, v) in env_overrides {
                spec = spec.with_env(k, v);
            }
            for warning in warnings {
                eprintln!("{warning}");
            }
            spec
        }
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(1);
        }
    };

    let mut spec = spec;
    apply_real_runner_override(&mut spec);
    let cleanup_spec = spec.clone();
    for warning in session_persistence_pre_run_warnings(
        parsed.save_session,
        parsed.cleanup_session,
        &output_plan.runner_name,
    ) {
        eprintln!("{warning}");
    }

    let runner = Runner::new();
    let show_thinking = resolve_show_thinking(&parsed, Some(&config));
    let sanitize_osc = resolve_sanitize_osc(&parsed, Some(&config));
    let forward_unknown_json = parsed.forward_unknown_json;
    let human_tty = resolve_human_tty(
        std::io::stdout().is_terminal(),
        env::var("FORCE_COLOR").ok().as_deref(),
        env::var("NO_COLOR").ok().as_deref(),
    );

    match output_plan.mode.as_str() {
        "text" | "json" => {
            let result = runner.run(spec);
            let stdout = sanitize_raw_output(&result.stdout, &output_plan.runner_name);
            let stderr = sanitize_raw_output(&result.stderr, &output_plan.runner_name);
            if !stdout.is_empty() {
                print!("{}", stdout);
            }
            if !stderr.is_empty() {
                eprint!("{}", stderr);
            }
            print_cleanup_warnings(
                parsed.cleanup_session,
                &output_plan.runner_name,
                &cleanup_spec,
                &result,
            );
            std::process::exit(result.exit_code)
        }
        "stream-text" | "stream-json" => {
            let result = runner.stream(spec, |channel, chunk| {
                if channel == "stdout" {
                    print!("{}", chunk);
                } else {
                    eprint!("{}", chunk);
                }
            });
            print_cleanup_warnings(
                parsed.cleanup_session,
                &output_plan.runner_name,
                &cleanup_spec,
                &result,
            );
            std::process::exit(result.exit_code)
        }
        "formatted" => {
            let result = runner.run(spec);
            let stderr = filtered_human_stderr(&result.stderr, &output_plan.runner_name);
            if !stderr.is_empty() {
                eprint!("{}", sanitize_human_output(&stderr, sanitize_osc));
            }
            let rendered = render_parsed(
                &parse_json_output(&result.stdout, output_plan.schema.as_deref().unwrap_or("")),
                show_thinking,
                human_tty,
            );
            if !rendered.is_empty() {
                println!("{}", sanitize_human_output(&rendered, sanitize_osc));
            }
            if forward_unknown_json {
                for raw_line in
                    parse_json_output(&result.stdout, output_plan.schema.as_deref().unwrap_or(""))
                        .unknown_json_lines
                {
                    eprintln!("{}", raw_line);
                }
            }
            print_cleanup_warnings(
                parsed.cleanup_session,
                &output_plan.runner_name,
                &cleanup_spec,
                &result,
            );
            std::process::exit(result.exit_code)
        }
        "stream-formatted" => {
            let stream_runner_name = output_plan.runner_name.clone();
            let processor = Arc::new(Mutex::new(StructuredStreamProcessor::new(
                output_plan.schema.as_deref().unwrap_or(""),
                FormattedRenderer::new(show_thinking, human_tty),
            )));
            let callback_processor = Arc::clone(&processor);
            let result = runner.stream(spec, move |channel, chunk| {
                if channel == "stderr" {
                    let filtered = filtered_human_stderr(chunk, &stream_runner_name);
                    if !filtered.is_empty() {
                        eprint!("{}", sanitize_human_output(&filtered, sanitize_osc));
                    }
                    return;
                }
                if let Ok(mut processor) = callback_processor.lock() {
                    let rendered = processor.feed(chunk);
                    if !rendered.is_empty() {
                        println!("{}", sanitize_human_output(&rendered, sanitize_osc));
                    }
                    if forward_unknown_json {
                        for raw_line in processor.take_unknown_json_lines() {
                            eprintln!("{}", raw_line);
                        }
                    }
                }
            });
            if let Ok(mut processor) = processor.lock() {
                let trailing = processor.finish();
                if !trailing.is_empty() {
                    println!("{}", sanitize_human_output(&trailing, sanitize_osc));
                }
                if forward_unknown_json {
                    for raw_line in processor.take_unknown_json_lines() {
                        eprintln!("{}", raw_line);
                    }
                }
            }
            print_cleanup_warnings(
                parsed.cleanup_session,
                &output_plan.runner_name,
                &cleanup_spec,
                &result,
            );
            std::process::exit(result.exit_code)
        }
        _ => {
            eprintln!("unsupported output mode");
            ExitCode::from(1)
        }
    }
}

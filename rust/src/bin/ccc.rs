use call_coding_clis::{
    load_config, parse_args, parse_json_output, print_help, print_usage, render_parsed,
    render_example_config, resolve_command, resolve_human_tty, resolve_output_plan,
    resolve_sanitize_osc, resolve_show_thinking,
    FormattedRenderer, Runner, StructuredStreamProcessor,
};
use std::env;
use std::io::IsTerminal;
use std::process::ExitCode;
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
        apply_real_runner_override, filtered_human_stderr, sanitize_human_output,
        sanitize_raw_output,
    };

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

    if args.len() == 1 && (args[0] == "--help" || args[0] == "-h") {
        print_help();
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
                for raw_line in parse_json_output(
                    &result.stdout,
                    output_plan.schema.as_deref().unwrap_or(""),
                )
                .unknown_json_lines
                {
                    eprintln!("{}", raw_line);
                }
            }
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
            std::process::exit(result.exit_code)
        }
        _ => {
            eprintln!("unsupported output mode");
            ExitCode::from(1)
        }
    }
}

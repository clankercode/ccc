use call_coding_clis::{
    find_alias_write_path, find_config_command_path, load_config, normalize_alias_name, parse_args,
    parse_json_output, print_help, print_usage, render_alias_block, render_example_config,
    render_parsed, resolve_command, resolve_human_tty, resolve_output_plan, resolve_sanitize_osc,
    resolve_show_thinking, write_alias_block, AliasDef, FormattedRenderer, Runner,
    StructuredStreamProcessor,
};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::sync::{Arc, Mutex};

const ADD_OUTPUT_MODES: &[&str] = &[
    "text",
    "stream-text",
    "json",
    "stream-json",
    "formatted",
    "stream-formatted",
];
const ADD_PROMPT_MODES: &[&str] = &["default", "prepend", "append"];
const KEEP_CURRENT_CHOICE: &str = "__keep_current__";
const UNSET_CHOICE: &str = "__unset__";
const MENU_RESET: &str = "\x1b[0m";

struct WizardChoice<'a> {
    label: &'a str,
    key: &'a str,
    value: &'a str,
    aliases: &'a [&'a str],
}

fn alias_has_any_field(alias: &AliasDef) -> bool {
    alias.runner.is_some()
        || alias.thinking.is_some()
        || alias.show_thinking.is_some()
        || alias.sanitize_osc.is_some()
        || alias.output_mode.is_some()
        || alias.provider.is_some()
        || alias.model.is_some()
        || alias.agent.is_some()
        || alias.prompt.is_some()
        || alias.prompt_mode.is_some()
}

fn parse_add_bool(value: &str) -> Result<bool, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "y" | "on" => Ok(true),
        "0" | "false" | "no" | "n" | "off" => Ok(false),
        _ => Err("boolean values must be true or false".to_string()),
    }
}

fn parse_add_thinking(value: &str) -> Result<i32, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "none" => Ok(0),
        "low" => Ok(1),
        "med" | "mid" | "medium" => Ok(2),
        "high" => Ok(3),
        "max" | "xhigh" => Ok(4),
        _ => match value.parse::<i32>() {
            Ok(parsed @ 0..=4) => Ok(parsed),
            Ok(_) => Err("thinking must be 0, 1, 2, 3, or 4".to_string()),
            Err(_) => Err(
                "thinking must be 0, 1, 2, 3, 4, none, low, medium, high, max, or xhigh"
                    .to_string(),
            ),
        },
    }
}

fn set_add_alias_field(alias: &mut AliasDef, field: &str, value: &str) -> Result<(), String> {
    match field {
        "runner" => alias.runner = Some(value.to_string()),
        "provider" => alias.provider = Some(value.to_string()),
        "model" => alias.model = Some(value.to_string()),
        "thinking" => alias.thinking = Some(parse_add_thinking(value)?),
        "show_thinking" => alias.show_thinking = Some(parse_add_bool(value)?),
        "sanitize_osc" => alias.sanitize_osc = Some(parse_add_bool(value)?),
        "output_mode" => {
            if !ADD_OUTPUT_MODES.contains(&value) {
                return Err(
                    "output_mode must be one of: text, stream-text, json, stream-json, formatted, stream-formatted"
                        .to_string(),
                );
            }
            alias.output_mode = Some(value.to_string());
        }
        "agent" => alias.agent = Some(value.to_string()),
        "prompt" => alias.prompt = Some(value.to_string()),
        "prompt_mode" => {
            if !ADD_PROMPT_MODES.contains(&value) {
                return Err("prompt_mode must be one of: default, prepend, append".to_string());
            }
            alias.prompt_mode = Some(value.to_string());
        }
        _ => {
            return Err(format!(
                "unknown ccc add option: --{}",
                field.replace('_', "-")
            ))
        }
    }
    Ok(())
}

fn parse_add_alias_args(
    args: &[String],
) -> Result<(bool, String, AliasDef, Vec<String>, bool, bool), String> {
    let mut global_only = false;
    let mut yes = false;
    let mut replace = false;
    let mut name: Option<String> = None;
    let mut alias = AliasDef::default();
    let mut unset_fields = Vec::new();
    let mut index = 0;
    while index < args.len() {
        let token = &args[index];
        if token == "-g" {
            global_only = true;
        } else if token == "--yes" {
            yes = true;
        } else if token == "--replace" {
            replace = true;
        } else if token == "--unset" {
            let value = args
                .get(index + 1)
                .ok_or_else(|| "--unset requires a value".to_string())?;
            if !is_add_alias_field(value) {
                return Err(format!("unknown alias field for --unset: {value}"));
            }
            unset_fields.push(value.to_string());
            index += 1;
        } else if token == "--show-thinking" {
            alias.show_thinking = Some(true);
        } else if token == "--no-show-thinking" {
            alias.show_thinking = Some(false);
        } else if token == "--sanitize-osc" {
            alias.sanitize_osc = Some(true);
        } else if token == "--no-sanitize-osc" {
            alias.sanitize_osc = Some(false);
        } else if let Some(field) = token.strip_prefix("--") {
            let value = args
                .get(index + 1)
                .ok_or_else(|| format!("{token} requires a value"))?;
            set_add_alias_field(&mut alias, &field.replace('-', "_"), value)?;
            index += 1;
        } else if name.is_none() {
            name = Some(normalize_alias_name(token)?);
        } else {
            return Err(format!("unexpected argument: {token}"));
        }
        index += 1;
    }
    let name = name.ok_or_else(|| "usage: ccc add [-g] <alias> [alias options]".to_string())?;
    for field in &unset_fields {
        if alias_field_is_set(&alias, field) {
            return Err(format!(
                "--unset {field} conflicts with --{}",
                field.replace('_', "-")
            ));
        }
    }
    Ok((global_only, name, alias, unset_fields, yes, replace))
}

fn run_add_alias_command(args: &[String]) -> ExitCode {
    let (global_only, name, alias, unset_fields, yes, replace) = match parse_add_alias_args(args) {
        Ok(value) => value,
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(1);
        }
    };

    let config_path = find_alias_write_path(global_only);
    println!("Config path: {}", config_path.display());

    let current_config = if config_path.exists() {
        Some(load_config(Some(&config_path)))
    } else {
        None
    };
    let current_alias = current_config
        .as_ref()
        .and_then(|config| config.aliases.get(&name))
        .cloned();
    let mut mode = if replace { "replace" } else { "modify" };
    if current_alias.is_some() && !yes {
        match ask_existing_alias_action(&name, current_alias.as_ref().unwrap()) {
            Ok(action) if action == "cancel" => {
                println!("Cancelled; alias @{name} unchanged");
                return ExitCode::from(0);
            }
            Ok(action) => mode = action,
            Err(error) => {
                eprintln!("{error}");
                return ExitCode::from(1);
            }
        }
    }

    let mut final_alias = if mode == "modify" {
        if let Some(current) = current_alias.clone() {
            merge_alias(&current, &alias, &unset_fields)
        } else {
            alias
        }
    } else {
        alias
    };

    if !yes {
        match prompt_alias_fields(&final_alias) {
            Ok(prompted) => final_alias = prompted,
            Err(error) => {
                eprintln!("{error}");
                return ExitCode::from(1);
            }
        }
        match render_alias_block(&name, &final_alias) {
            Ok(block) => print!("{block}"),
            Err(error) => {
                eprintln!("{error}");
                return ExitCode::from(1);
            }
        }
        match confirm("Write this alias?") {
            Ok(true) => {}
            Ok(false) => {
                println!("Cancelled; alias @{name} unchanged");
                return ExitCode::from(0);
            }
            Err(error) => {
                eprintln!("{error}");
                return ExitCode::from(1);
            }
        }
    } else if current_alias.is_none() && !alias_has_any_field(&final_alias) {
        eprintln!("ccc add --yes requires at least one alias field");
        return ExitCode::from(1);
    }

    if let Err(error) = write_alias_block(&config_path, &name, &final_alias) {
        eprintln!("{error}");
        return ExitCode::from(1);
    }
    match render_alias_block(&name, &final_alias) {
        Ok(block) => print!("{}", format_written_alias(&name, &block)),
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::from(1);
        }
    }
    ExitCode::from(0)
}

fn is_add_alias_field(field: &str) -> bool {
    matches!(
        field,
        "runner"
            | "provider"
            | "model"
            | "thinking"
            | "show_thinking"
            | "sanitize_osc"
            | "output_mode"
            | "agent"
            | "prompt"
            | "prompt_mode"
    )
}

fn alias_field_is_set(alias: &AliasDef, field: &str) -> bool {
    match field {
        "runner" => alias.runner.is_some(),
        "provider" => alias.provider.is_some(),
        "model" => alias.model.is_some(),
        "thinking" => alias.thinking.is_some(),
        "show_thinking" => alias.show_thinking.is_some(),
        "sanitize_osc" => alias.sanitize_osc.is_some(),
        "output_mode" => alias.output_mode.is_some(),
        "agent" => alias.agent.is_some(),
        "prompt" => alias.prompt.is_some(),
        "prompt_mode" => alias.prompt_mode.is_some(),
        _ => false,
    }
}

fn unset_alias_field(alias: &mut AliasDef, field: &str) {
    match field {
        "runner" => alias.runner = None,
        "provider" => alias.provider = None,
        "model" => alias.model = None,
        "thinking" => alias.thinking = None,
        "show_thinking" => alias.show_thinking = None,
        "sanitize_osc" => alias.sanitize_osc = None,
        "output_mode" => alias.output_mode = None,
        "agent" => alias.agent = None,
        "prompt" => alias.prompt = None,
        "prompt_mode" => alias.prompt_mode = None,
        _ => {}
    }
}

fn merge_alias(current: &AliasDef, overlay: &AliasDef, unset_fields: &[String]) -> AliasDef {
    let mut result = current.clone();
    if overlay.runner.is_some() {
        result.runner = overlay.runner.clone();
    }
    if overlay.provider.is_some() {
        result.provider = overlay.provider.clone();
    }
    if overlay.model.is_some() {
        result.model = overlay.model.clone();
    }
    if overlay.thinking.is_some() {
        result.thinking = overlay.thinking;
    }
    if overlay.show_thinking.is_some() {
        result.show_thinking = overlay.show_thinking;
    }
    if overlay.sanitize_osc.is_some() {
        result.sanitize_osc = overlay.sanitize_osc;
    }
    if overlay.output_mode.is_some() {
        result.output_mode = overlay.output_mode.clone();
    }
    if overlay.agent.is_some() {
        result.agent = overlay.agent.clone();
    }
    if overlay.prompt.is_some() {
        result.prompt = overlay.prompt.clone();
    }
    if overlay.prompt_mode.is_some() {
        result.prompt_mode = overlay.prompt_mode.clone();
    }
    for field in unset_fields {
        unset_alias_field(&mut result, field);
    }
    result
}

fn read_prompt(prompt: &str) -> Result<String, String> {
    print!("{prompt}");
    io::stdout()
        .flush()
        .map_err(|error| format!("failed to write prompt: {error}"))?;
    let mut answer = String::new();
    let bytes = io::stdin()
        .read_line(&mut answer)
        .map_err(|error| format!("failed to read answer: {error}"))?;
    if bytes == 0 {
        return Err("input ended before the wizard completed".to_string());
    }
    Ok(answer.trim().to_string())
}

fn choice_marker(choice: &WizardChoice<'_>) -> String {
    if choice.key.is_empty() {
        return choice.label.to_string();
    }
    if choice.key.len() == 1 && choice.label.starts_with(choice.key) {
        return format!("[{}]{}", choice.key, &choice.label[1..]);
    }
    format!("[{}] {}", choice.key, choice.label)
}

fn menu_color_enabled() -> bool {
    if env::var("FORCE_COLOR").is_ok_and(|value| !value.is_empty()) {
        return true;
    }
    if env::var("NO_COLOR").is_ok_and(|value| !value.is_empty()) {
        return false;
    }
    io::stdout().is_terminal()
}

fn menu_style(text: &str, code: &str, enabled: bool) -> String {
    if enabled {
        format!("\x1b[{code}m{text}{MENU_RESET}")
    } else {
        text.to_string()
    }
}

fn format_written_alias(name: &str, block: &str) -> String {
    let heading = menu_style(
        &format!("✓  Alias @{name} written"),
        "1;32",
        menu_color_enabled(),
    );
    let indented_block = block
        .lines()
        .map(|line| format!("  {line}\n"))
        .collect::<String>();
    format!("\n{heading}\n\n{indented_block}")
}

fn choose(
    prompt: &str,
    choices: &[WizardChoice<'_>],
    default: Option<usize>,
    blank_value: Option<&str>,
) -> Result<String, String> {
    let markers = choices
        .iter()
        .map(choice_marker)
        .collect::<Vec<_>>()
        .join(", ");
    loop {
        let color = menu_color_enabled();
        let default_label = if let Some(index) = default {
            let choice = &choices[index - 1];
            if choice.key.is_empty() {
                choice.label
            } else {
                choice.key
            }
        } else if blank_value.is_some() {
            "keep"
        } else {
            "none"
        };
        let answer = read_prompt(&format!(
            "{} {}: \n{}\n  {} {} | {} ",
            menu_style(prompt, "1;36", color),
            menu_style(&format!("(1-{})", choices.len()), "2", color),
            menu_style(&format!("  {markers}"), "32", color),
            menu_style("default", "2", color),
            menu_style(default_label, "33", color),
            menu_style("choice >", "1;36", color),
        ))?
        .to_ascii_lowercase();
        if answer.is_empty() {
            if let Some(index) = default {
                return Ok(choices[index - 1].value.to_string());
            }
            return Ok(blank_value.unwrap_or("").to_string());
        }
        for (index, choice) in choices.iter().enumerate() {
            if answer == (index + 1).to_string()
                || answer == choice.label
                || answer == choice.key
                || choice.aliases.iter().any(|alias| answer == *alias)
            {
                return Ok(choice.value.to_string());
            }
        }
        let options = (1..=choices.len())
            .map(|index| index.to_string())
            .collect::<Vec<_>>()
            .join(", ");
        println!(
            "{}{options}.",
            menu_style("Please choose one of: ", "31", color)
        );
    }
}

fn choose_optional_field(
    label: &str,
    suffix: &str,
    choices: &[WizardChoice<'_>],
) -> Result<String, String> {
    choose(
        &format!("{label}{suffix}"),
        choices,
        None,
        Some(KEEP_CURRENT_CHOICE),
    )
}

fn ask_existing_alias_action(name: &str, current_alias: &AliasDef) -> Result<&'static str, String> {
    println!("Alias @{name} already exists:");
    print!("{}", render_alias_block(name, current_alias)?);
    let action = choose(
        "Existing alias action",
        &[
            WizardChoice {
                label: "modify",
                key: "m",
                value: "modify",
                aliases: &["modify"],
            },
            WizardChoice {
                label: "replace",
                key: "r",
                value: "replace",
                aliases: &["replace"],
            },
            WizardChoice {
                label: "cancel",
                key: "c",
                value: "cancel",
                aliases: &["cancel"],
            },
        ],
        Some(1),
        None,
    )?;
    match action.as_str() {
        "modify" => Ok("modify"),
        "replace" => Ok("replace"),
        _ => Ok("cancel"),
    }
}

fn prompt_alias_fields(alias: &AliasDef) -> Result<AliasDef, String> {
    let mut result = alias.clone();
    for (field, label, current) in [
        ("runner", "Runner", alias.runner.clone()),
        ("provider", "Provider", alias.provider.clone()),
        ("model", "Model", alias.model.clone()),
        (
            "thinking",
            "Thinking 0-4",
            alias.thinking.map(|value| value.to_string()),
        ),
        (
            "show_thinking",
            "Show thinking true/false",
            alias.show_thinking.map(|value| value.to_string()),
        ),
        (
            "sanitize_osc",
            "Sanitize OSC true/false",
            alias.sanitize_osc.map(|value| value.to_string()),
        ),
        ("output_mode", "Output mode", alias.output_mode.clone()),
        ("agent", "Agent", alias.agent.clone()),
        ("prompt", "Prompt", alias.prompt.clone()),
        ("prompt_mode", "Prompt mode", alias.prompt_mode.clone()),
    ] {
        let suffix = current
            .as_ref()
            .map(|value| format!(" [{value}]"))
            .unwrap_or_else(|| " [default]".to_string());
        if field == "thinking" {
            let choice = choose_optional_field(
                label,
                &suffix,
                &[
                    WizardChoice {
                        label: "unset",
                        key: "u",
                        value: UNSET_CHOICE,
                        aliases: &["unset", "default"],
                    },
                    WizardChoice {
                        label: "none",
                        key: "n",
                        value: "none",
                        aliases: &["none"],
                    },
                    WizardChoice {
                        label: "low",
                        key: "l",
                        value: "low",
                        aliases: &["low"],
                    },
                    WizardChoice {
                        label: "medium",
                        key: "m",
                        value: "medium",
                        aliases: &["medium", "med", "mid"],
                    },
                    WizardChoice {
                        label: "high",
                        key: "h",
                        value: "high",
                        aliases: &["high"],
                    },
                    WizardChoice {
                        label: "xhigh",
                        key: "x",
                        value: "xhigh",
                        aliases: &["xhigh", "max"],
                    },
                ],
            )?;
            if choice == KEEP_CURRENT_CHOICE {
                continue;
            }
            if choice == UNSET_CHOICE {
                unset_alias_field(&mut result, field);
            } else {
                set_add_alias_field(&mut result, field, &choice)?;
            }
            continue;
        }
        if matches!(field, "show_thinking" | "sanitize_osc") {
            let choice = choose_optional_field(
                label,
                &suffix,
                &[
                    WizardChoice {
                        label: "unset",
                        key: "u",
                        value: UNSET_CHOICE,
                        aliases: &["unset", "default"],
                    },
                    WizardChoice {
                        label: "true",
                        key: "t",
                        value: "true",
                        aliases: &["true", "yes", "y", "on"],
                    },
                    WizardChoice {
                        label: "false",
                        key: "f",
                        value: "false",
                        aliases: &["false", "no", "n", "off"],
                    },
                ],
            )?;
            if choice == KEEP_CURRENT_CHOICE {
                continue;
            }
            if choice == UNSET_CHOICE {
                unset_alias_field(&mut result, field);
            } else {
                set_add_alias_field(&mut result, field, &choice)?;
            }
            continue;
        }
        if field == "output_mode" {
            let choice = choose_optional_field(
                label,
                &suffix,
                &[
                    WizardChoice {
                        label: "unset",
                        key: "u",
                        value: UNSET_CHOICE,
                        aliases: &["unset", "default"],
                    },
                    WizardChoice {
                        label: "text",
                        key: "t",
                        value: "text",
                        aliases: &["text"],
                    },
                    WizardChoice {
                        label: "stream-text",
                        key: "st",
                        value: "stream-text",
                        aliases: &["stream-text"],
                    },
                    WizardChoice {
                        label: "json",
                        key: "j",
                        value: "json",
                        aliases: &["json"],
                    },
                    WizardChoice {
                        label: "stream-json",
                        key: "sj",
                        value: "stream-json",
                        aliases: &["stream-json"],
                    },
                    WizardChoice {
                        label: "formatted",
                        key: "f",
                        value: "formatted",
                        aliases: &["formatted"],
                    },
                    WizardChoice {
                        label: "stream-formatted",
                        key: "sf",
                        value: "stream-formatted",
                        aliases: &["stream-formatted"],
                    },
                ],
            )?;
            if choice == KEEP_CURRENT_CHOICE {
                continue;
            }
            if choice == UNSET_CHOICE {
                unset_alias_field(&mut result, field);
            } else {
                set_add_alias_field(&mut result, field, &choice)?;
            }
            continue;
        }
        if field == "prompt_mode" {
            let choice = choose_optional_field(
                label,
                &suffix,
                &[
                    WizardChoice {
                        label: "unset",
                        key: "u",
                        value: UNSET_CHOICE,
                        aliases: &["unset"],
                    },
                    WizardChoice {
                        label: "default",
                        key: "d",
                        value: "default",
                        aliases: &["default"],
                    },
                    WizardChoice {
                        label: "prepend",
                        key: "p",
                        value: "prepend",
                        aliases: &["prepend"],
                    },
                    WizardChoice {
                        label: "append",
                        key: "a",
                        value: "append",
                        aliases: &["append"],
                    },
                ],
            )?;
            if choice == KEEP_CURRENT_CHOICE {
                continue;
            }
            if choice == UNSET_CHOICE {
                unset_alias_field(&mut result, field);
            } else {
                set_add_alias_field(&mut result, field, &choice)?;
            }
            continue;
        }
        let answer = read_prompt(&format!("{label}{suffix}: "))?;
        if answer.is_empty() {
            continue;
        }
        if matches!(answer.as_str(), "default" | "unset") {
            unset_alias_field(&mut result, field);
        } else {
            set_add_alias_field(&mut result, field, &answer)?;
        }
    }
    Ok(result)
}

fn confirm(prompt: &str) -> Result<bool, String> {
    let answer = choose(
        prompt,
        &[
            WizardChoice {
                label: "yes",
                key: "y",
                value: "yes",
                aliases: &["yes"],
            },
            WizardChoice {
                label: "no",
                key: "n",
                value: "no",
                aliases: &["no"],
            },
        ],
        Some(2),
        None,
    )?;
    Ok(answer == "yes")
}

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

    if args.first().map(String::as_str) == Some("add") {
        return run_add_alias_command(&args[1..]);
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
    let requested_output_plan = match resolve_output_plan(&parsed, Some(&config)) {
        Ok(plan) => plan,
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(1);
        }
    };
    let show_thinking = resolve_show_thinking(&parsed, Some(&config));
    let text_mode_with_visible_work = requested_output_plan.mode == "text"
        && show_thinking
        && matches!(
            requested_output_plan.runner_name.as_str(),
            "oc" | "opencode"
        );
    let mut command_parsed = parsed.clone();
    if text_mode_with_visible_work {
        command_parsed.output_mode = Some("stream-formatted".to_string());
    }
    let command_output_plan = match resolve_output_plan(&command_parsed, Some(&config)) {
        Ok(plan) => plan,
        Err(msg) => {
            eprintln!("{msg}");
            return ExitCode::from(1);
        }
    };
    let output_plan = requested_output_plan.clone();
    let spec = match resolve_command(&command_parsed, Some(&config)) {
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
    let sanitize_osc = resolve_sanitize_osc(&parsed, Some(&config));
    let forward_unknown_json = parsed.forward_unknown_json;
    let human_tty = resolve_human_tty(
        std::io::stdout().is_terminal(),
        env::var("FORCE_COLOR").ok().as_deref(),
        env::var("NO_COLOR").ok().as_deref(),
    );

    match output_plan.mode.as_str() {
        "json" => {
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
        _ if text_mode_with_visible_work => {
            let stream_runner_name = command_output_plan.runner_name.clone();
            let processor = Arc::new(Mutex::new(StructuredStreamProcessor::new(
                command_output_plan.schema.as_deref().unwrap_or(""),
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
                }
            });
            if let Ok(mut processor) = processor.lock() {
                let trailing = processor.finish();
                if !trailing.is_empty() {
                    println!("{}", sanitize_human_output(&trailing, sanitize_osc));
                }
            }
            print_cleanup_warnings(
                parsed.cleanup_session,
                &command_output_plan.runner_name,
                &cleanup_spec,
                &result,
            );
            std::process::exit(result.exit_code)
        }
        "text" => {
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

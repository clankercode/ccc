//! Decide when a preset may retry on another model.
//!
//! Fallbacks run only after a capacity or overload failure that produced no
//! assistant output. Most models stay on the same runner. Model ids in
//! [`FALLBACK_MODEL_RUNNERS`] are retried on the mapped runner instead.

use serde_json::Value;

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn has_status_401(haystack: &str) -> bool {
    haystack.match_indices("401").any(|(index, value)| {
        let before_ok = index == 0 || !haystack.as_bytes()[index - 1].is_ascii_digit();
        let after = index + value.len();
        let after_ok = after >= haystack.len() || !haystack.as_bytes()[after].is_ascii_digit();
        before_ok && after_ok
    })
}

const NON_OUTPUT_EVENT_TYPES: &[&str] = &["error", "turn.failed", "thread.started", "turn.started"];
const NON_OUTPUT_ITEM_TYPES: &[&str] = &["error", "warning"];

/// Exact model ids that cannot run on the preset's runner.
/// Lookup is case-sensitive; add new cross-runner targets here rather than guessing.
pub(crate) fn fallback_model_runners() -> &'static [(&'static str, &'static str)] {
    &[
        ("glm-5.3", "grok"),
        ("llmp-glm-5-3", "grok"),
        ("glm-5.3-flash", "grok"),
    ]
}

pub(crate) const DISALLOWED_FALLBACK_REASON: &str =
    "MiniMax, Claude, and Astra models are not fallback targets";

pub(crate) fn canonical_runner_name(name: &str) -> String {
    match name.to_ascii_lowercase().as_str() {
        "oc" | "opencode" => "opencode".to_string(),
        "cc" | "claude" => "claude".to_string(),
        "c" | "cx" | "codex" => "codex".to_string(),
        "k" | "kimi" => "kimi".to_string(),
        "cu" | "cursor" => "cursor".to_string(),
        "g" | "gemini" => "gemini".to_string(),
        "rc" | "roocode" => "roocode".to_string(),
        "cr" | "crush" => "crush".to_string(),
        "p" | "pi" => "pi".to_string(),
        "gb" | "grok" => "grok".to_string(),
        other => other.to_string(),
    }
}

pub(crate) fn fallback_runner_for_model(model: &str) -> Option<String> {
    fallback_model_runners()
        .iter()
        .find(|(candidate, _)| *candidate == model)
        .map(|(_, runner)| canonical_runner_name(runner))
}

pub(crate) fn is_disallowed_fallback_model(model: &str) -> bool {
    let lowered = model.to_ascii_lowercase();
    lowered.contains("minimax") || lowered.contains("claude") || lowered.contains("astra")
}

pub(crate) fn is_disallowed_fallback_runner(runner_name: &str) -> bool {
    matches!(runner_name.to_ascii_lowercase().as_str(), "cc" | "claude")
}

pub(crate) fn is_auth_failure(stdout: &str, stderr: &str) -> bool {
    let blob = format!("{stdout}\n{stderr}").to_ascii_lowercase();
    contains_any(
        &blob,
        &[
            "authentication_error",
            "no usable account credential",
            "needs reauthentication",
            "unauthorized",
            "invalid api key",
            "invalid_api_key",
            "not logged in",
            "please run /login",
        ],
    ) || has_status_401(&blob)
}

pub(crate) fn is_capacity_failure(stdout: &str, stderr: &str) -> bool {
    let blob = format!("{stdout}\n{stderr}").to_ascii_lowercase();
    contains_any(
        &blob,
        &[
            "at capacity",
            "server_overloaded",
            "overloaded_error",
            "model is overloaded",
            "model overloaded",
            "overloaded",
        ],
    )
}

fn json_line_is_non_output(line: &str) -> Option<bool> {
    if !line.starts_with('{') {
        return None;
    }
    let value: Value = serde_json::from_str(line).ok()?;
    let event_type = value.get("type").and_then(Value::as_str).unwrap_or("");
    if NON_OUTPUT_EVENT_TYPES.contains(&event_type) {
        return Some(true);
    }
    if event_type == "item.completed" {
        let item_type = value
            .get("item")
            .and_then(|item| item.get("type"))
            .and_then(Value::as_str)
            .unwrap_or("");
        return Some(NON_OUTPUT_ITEM_TYPES.contains(&item_type));
    }
    if event_type.is_empty() {
        return None;
    }
    Some(false)
}

pub(crate) fn assistant_output_started(stdout: &str) -> bool {
    let mut saw_line = false;
    for raw_line in stdout.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        saw_line = true;
        match json_line_is_non_output(line) {
            Some(true) => {}
            Some(false) | None => return true,
        }
    }
    if saw_line {
        false
    } else {
        !stdout.trim().is_empty()
    }
}

pub(crate) fn failure_allows_fallback(
    exit_code: i32,
    timed_out: bool,
    stdout: &str,
    stderr: &str,
) -> bool {
    if timed_out || exit_code == 0 {
        return false;
    }
    if assistant_output_started(stdout) {
        return false;
    }
    if is_auth_failure(stdout, stderr) {
        return false;
    }
    is_capacity_failure(stdout, stderr)
}

pub(crate) fn terminal_notice(
    label: &str,
    exit_code: i32,
    timed_out: bool,
    stdout: &str,
    stderr: &str,
) -> String {
    if exit_code == 0 && !timed_out {
        return format!("ccc: ran model {label}\n");
    }
    if assistant_output_started(stdout) {
        return format!("ccc: model {label} failed after producing output; not falling back\n");
    }
    if is_auth_failure(stdout, stderr) {
        return format!(
            "ccc: model {label} failed with an authentication error; not falling back\n"
        );
    }
    if is_capacity_failure(stdout, stderr) {
        return format!(
            "ccc: model {label} failed with a capacity error; no fallback models left\n"
        );
    }
    format!("ccc: model {label} failed; not falling back\n")
}

pub(crate) fn trying_notice(current: &str, next: &str, runner: Option<&str>) -> String {
    match runner {
        Some(runner) => format!(
            "ccc: model {current} is at capacity before producing output; trying {next} on {runner}\n"
        ),
        None => {
            format!("ccc: model {current} is at capacity before producing output; trying {next}\n")
        }
    }
}

pub(crate) fn session_save_notice(runner_name: &str) -> Option<String> {
    let display = canonical_runner_name(runner_name);
    if !matches!(
        display.as_str(),
        "opencode" | "kimi" | "crush" | "roocode" | "cursor" | "gemini" | "grok"
    ) {
        return None;
    }
    Some(format!(
        "warning: runner \"{display}\" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n"
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        assistant_output_started, failure_allows_fallback, is_disallowed_fallback_model,
        is_disallowed_fallback_runner,
    };

    #[test]
    fn capacity_before_output_may_fall_back() {
        assert!(failure_allows_fallback(
            1,
            false,
            "",
            "Selected model is at capacity. Please try a different model.\nserver_overloaded\n",
        ));
    }

    #[test]
    fn auth_failure_does_not_fall_back() {
        assert!(!failure_allows_fallback(
            1,
            false,
            "",
            "unexpected status 401 Unauthorized: OpenAI account pool has no usable account credential\n",
        ));
    }

    #[test]
    fn output_blocks_fallback() {
        assert!(assistant_output_started("partial answer\n"));
        assert!(!failure_allows_fallback(
            1,
            false,
            "partial answer\n",
            "Selected model is at capacity\n",
        ));
    }

    #[test]
    fn error_only_json_is_not_assistant_output() {
        let stdout = "{\"type\":\"error\",\"message\":\"Selected model is at capacity\"}\n{\"type\":\"turn.failed\",\"error\":{\"message\":\"server_overloaded\"}}\n";
        assert!(!assistant_output_started(stdout));
        assert!(failure_allows_fallback(1, false, stdout, ""));
    }

    #[test]
    fn claude_and_minimax_targets_are_rejected() {
        assert!(is_disallowed_fallback_runner("claude"));
        assert!(is_disallowed_fallback_runner("cc"));
        assert!(!is_disallowed_fallback_runner("codex"));
        assert!(is_disallowed_fallback_model("MiniMax-M3"));
        assert!(is_disallowed_fallback_model("claude-sonnet-4"));
        assert!(is_disallowed_fallback_model("gpt-6-astra"));
        assert!(is_disallowed_fallback_model("GPT-6-Astra--fast"));
        assert!(is_disallowed_fallback_model("openai/gpt-6-astra"));
        assert!(!is_disallowed_fallback_model("gpt-6-sol"));
        assert!(!is_disallowed_fallback_model("glm-5.3"));
    }

    #[test]
    fn glm_models_map_to_grok() {
        assert_eq!(
            super::fallback_runner_for_model("glm-5.3").as_deref(),
            Some("grok")
        );
        assert_eq!(
            super::fallback_runner_for_model("llmp-glm-5-3").as_deref(),
            Some("grok")
        );
        assert_eq!(
            super::fallback_runner_for_model("glm-5.3-flash").as_deref(),
            Some("grok")
        );
        assert_eq!(super::fallback_runner_for_model("GLM-5.3"), None);
        assert_eq!(super::fallback_runner_for_model("gpt-6-sol"), None);
        assert_eq!(super::canonical_runner_name("cx"), "codex");
        assert_eq!(super::canonical_runner_name("gb"), "grok");
    }
}

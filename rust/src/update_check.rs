use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

const CRATES_API_URL: &str = "https://crates.io/api/v1/crates/ccc";
const GITHUB_RELEASE_URL: &str = "https://api.github.com/repos/clankercode/ccc/releases/latest";
const DEFAULT_INTERVAL_HOURS: u64 = 24;
const DEFAULT_FETCH_TIMEOUT_SECS: u64 = 2;
const CACHE_DIR_NAME: &str = "ccc";
const CACHE_FILE_NAME: &str = "update-check.json";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UpdateSettings {
    pub check: bool,
    pub auto_update: bool,
    pub interval_hours: u64,
}

impl Default for UpdateSettings {
    fn default() -> Self {
        Self {
            check: true,
            auto_update: false,
            interval_hours: DEFAULT_INTERVAL_HOURS,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct UpdateCache {
    pub checked_at: f64,
    pub current: String,
    pub latest: String,
    pub source: String,
}

impl UpdateCache {
    pub fn update_available(&self) -> bool {
        version_is_newer(&self.latest, &self.current)
    }
}

pub fn resolve_update_settings(
    config_check: bool,
    config_auto_update: bool,
    config_interval_hours: u64,
) -> UpdateSettings {
    let mut settings = UpdateSettings {
        check: env_bool("CCC_UPDATE_CHECK", config_check),
        auto_update: env_bool("CCC_AUTO_UPDATE", config_auto_update),
        interval_hours: if config_interval_hours == 0 {
            DEFAULT_INTERVAL_HOURS
        } else {
            config_interval_hours
        },
    };
    if let Ok(raw) = env::var("CCC_UPDATE_INTERVAL_HOURS") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            if let Ok(parsed) = trimmed.parse::<u64>() {
                if parsed > 0 {
                    settings.interval_hours = parsed;
                }
            }
        }
    }
    settings
}

pub fn current_version() -> String {
    option_env!("CCC_VERSION")
        .unwrap_or(env!("CARGO_PKG_VERSION"))
        .to_string()
}

pub fn resolve_cache_path() -> PathBuf {
    if let Ok(explicit) = env::var("CCC_UPDATE_CACHE") {
        let trimmed = explicit.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }
    if let Ok(xdg_cache) = env::var("XDG_CACHE_HOME") {
        let trimmed = xdg_cache.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed)
                .join(CACHE_DIR_NAME)
                .join(CACHE_FILE_NAME);
        }
    }
    home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".cache")
        .join(CACHE_DIR_NAME)
        .join(CACHE_FILE_NAME)
}

pub fn load_cache(path: &Path) -> Option<UpdateCache> {
    let text = fs::read_to_string(path).ok()?;
    let payload: Value = serde_json::from_str(&text).ok()?;
    let checked_at = payload.get("checked_at")?.as_f64()?;
    let current = payload.get("current")?.as_str()?.to_string();
    let latest = payload.get("latest")?.as_str()?.to_string();
    if current.is_empty() || latest.is_empty() {
        return None;
    }
    let source = payload
        .get("source")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Some(UpdateCache {
        checked_at,
        current,
        latest,
        source,
    })
}

pub fn save_cache(cache: &UpdateCache, path: &Path) -> bool {
    if let Some(parent) = path.parent() {
        if fs::create_dir_all(parent).is_err() {
            return false;
        }
    }
    let payload = serde_json::json!({
        "checked_at": cache.checked_at,
        "current": cache.current,
        "latest": cache.latest,
        "source": cache.source,
    });
    match fs::write(path, format!("{payload}\n")) {
        Ok(()) => true,
        Err(_) => false,
    }
}

pub fn cache_is_fresh(cache: &UpdateCache, interval_hours: u64, now: f64) -> bool {
    let max_age = interval_hours.max(1) as f64 * 3600.0;
    (now - cache.checked_at) < max_age
}

pub fn parse_version_tuple(version: &str) -> Option<(u64, u64, u64)> {
    let text = version.trim();
    if text.is_empty() || text.eq_ignore_ascii_case("unknown") {
        return None;
    }
    let stripped = text.strip_prefix('v').unwrap_or(text);
    let core = stripped
        .split_once(['-', '+'])
        .map(|(head, _)| head)
        .unwrap_or(stripped);
    let mut parts = core.split('.');
    let major = parts.next()?.parse::<u64>().ok()?;
    let minor = parts
        .next()
        .map(|part| part.parse::<u64>().ok())
        .unwrap_or(Some(0))?;
    let patch = parts
        .next()
        .map(|part| part.parse::<u64>().ok())
        .unwrap_or(Some(0))?;
    if parts.next().is_some() {
        // Allow only major.minor.patch core numbers.
    }
    Some((major, minor, patch))
}

pub fn version_is_newer(latest: &str, current: &str) -> bool {
    match (parse_version_tuple(latest), parse_version_tuple(current)) {
        (Some(latest_parts), Some(current_parts)) => latest_parts > current_parts,
        _ => false,
    }
}

pub fn fetch_latest_version(timeout_secs: u64) -> Option<(String, String)> {
    if let Some(body) = http_get(CRATES_API_URL, timeout_secs) {
        if let Some(latest) = parse_crates_latest(&body) {
            return Some((latest, "crates.io".to_string()));
        }
    }
    if let Some(body) = http_get(GITHUB_RELEASE_URL, timeout_secs) {
        if let Some(latest) = parse_github_latest(&body) {
            return Some((latest, "github".to_string()));
        }
    }
    None
}

pub fn refresh_cache(
    current: &str,
    interval_hours: u64,
    timeout_secs: u64,
    cache_path: &Path,
    force: bool,
    now: f64,
) -> Option<UpdateCache> {
    let existing = load_cache(cache_path);
    if let Some(ref cache) = existing {
        if !force && cache_is_fresh(cache, interval_hours, now) {
            return existing;
        }
    }
    let (latest, source) = fetch_latest_version(timeout_secs)?;
    let cache = UpdateCache {
        checked_at: now,
        current: current.to_string(),
        latest,
        source,
    };
    save_cache(&cache, cache_path);
    Some(cache)
}

pub fn format_update_notice(current: &str, latest: &str, auto_update: bool) -> String {
    if auto_update {
        format!(
            "warning: ccc {latest} is available (you have {current}); starting background update via `cargo install ccc`"
        )
    } else {
        format!(
            "warning: ccc {latest} is available (you have {current}); update with: cargo install ccc"
        )
    }
}

pub fn detect_install_method(executable: Option<&str>) -> String {
    let raw = executable
        .map(str::to_string)
        .or_else(|| env::args().next())
        .unwrap_or_default();
    let path = PathBuf::from(&raw);
    let text = path.to_string_lossy().replace('\\', "/");
    if text.contains("/cargo/bin/") || text.ends_with("/.cargo/bin/ccc") {
        return "cargo".to_string();
    }
    if let Some(home) = home_dir() {
        let cargo_bin = home.join(".cargo").join("bin").join("ccc");
        if cargo_bin.exists() {
            if let (Ok(left), Ok(right)) = (fs::canonicalize(&cargo_bin), fs::canonicalize(&path))
            {
                if left == right {
                    return "cargo".to_string();
                }
            }
        }
    }
    "unknown".to_string()
}

pub fn spawn_background_update(log_path: Option<&Path>) -> Option<PathBuf> {
    if detect_install_method(None) != "cargo" {
        return None;
    }
    let log = log_path
        .map(Path::to_path_buf)
        .unwrap_or_else(|| resolve_cache_path().with_file_name("auto-update.log"));
    if let Some(parent) = log.parent() {
        fs::create_dir_all(parent).ok()?;
    }
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log)
        .ok()?;
    let _ = writeln!(
        file,
        "\n--- auto-update started {} ---",
        unix_timestamp_secs()
    );
    let stdout = file.try_clone().ok()?;
    Command::new("cargo")
        .args(["install", "ccc", "--force"])
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(file))
        .spawn()
        .ok()?;
    Some(log)
}

pub fn emit_post_run_update_notice(settings: &UpdateSettings) -> Option<String> {
    if !settings.check {
        return None;
    }
    let current = current_version();
    let cache_path = resolve_cache_path();
    let now = unix_timestamp();
    let cache = refresh_cache(
        &current,
        settings.interval_hours,
        DEFAULT_FETCH_TIMEOUT_SECS,
        &cache_path,
        false,
        now,
    )?;
    if !version_is_newer(&cache.latest, &current) {
        return None;
    }
    let notice = format_update_notice(&current, &cache.latest, settings.auto_update);
    eprintln!("{notice}");
    if settings.auto_update {
        match spawn_background_update(None) {
            Some(log) => eprintln!("warning: auto-update log: {}", log.display()),
            None => {
                if detect_install_method(None) != "cargo" {
                    eprintln!(
                        "warning: auto_update is enabled but this ccc install is not cargo-based; update manually with: cargo install ccc"
                    );
                }
            }
        }
    }
    Some(notice)
}

fn http_get(url: &str, timeout_secs: u64) -> Option<String> {
    let current = current_version();
    let user_agent = format!("ccc/{current} (https://github.com/clankercode/ccc)");
    let timeout = timeout_secs.max(1).to_string();
    let output = Command::new("curl")
        .args([
            "-fsSL",
            "--max-time",
            &timeout,
            "-H",
            &format!("User-Agent: {user_agent}"),
            "-H",
            "Accept: application/json",
            url,
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8(output.stdout).ok()
}

fn parse_crates_latest(body: &str) -> Option<String> {
    let payload: Value = serde_json::from_str(body).ok()?;
    let crate_obj = payload.get("crate")?;
    for key in ["max_stable_version", "max_version", "newest_version"] {
        if let Some(value) = crate_obj.get(key).and_then(Value::as_str) {
            let cleaned = value.trim().trim_start_matches('v');
            if parse_version_tuple(cleaned).is_some() {
                return Some(cleaned.to_string());
            }
        }
    }
    None
}

fn parse_github_latest(body: &str) -> Option<String> {
    let payload: Value = serde_json::from_str(body).ok()?;
    let tag = payload
        .get("tag_name")
        .or_else(|| payload.get("name"))
        .and_then(Value::as_str)?;
    let cleaned = tag.trim().trim_start_matches('v');
    if parse_version_tuple(cleaned).is_some() {
        Some(cleaned.to_string())
    } else {
        None
    }
}

fn env_bool(name: &str, default: bool) -> bool {
    match env::var(name) {
        Ok(value) => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "" | "1" | "true" | "yes" | "on" => true,
                "0" | "false" | "no" | "off" | "n" => false,
                _ => default,
            }
        }
        Err(_) => default,
    }
}

fn unix_timestamp() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs_f64())
        .unwrap_or(0.0)
}

fn unix_timestamp_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("USERPROFILE").map(PathBuf::from))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn version_compare_handles_simple_semver() {
        assert!(version_is_newer("0.5.0", "0.4.1"));
        assert!(!version_is_newer("0.4.1", "0.4.1"));
        assert!(!version_is_newer("0.4.0", "0.4.1"));
        assert!(version_is_newer("v1.2.3", "1.2.2"));
    }

    #[test]
    fn parse_crates_and_github_payloads() {
        let crates = r#"{"crate":{"max_stable_version":"0.5.0","max_version":"0.5.0"}}"#;
        assert_eq!(parse_crates_latest(crates).as_deref(), Some("0.5.0"));
        let github = r#"{"tag_name":"v0.5.1","name":"ccc 0.5.1"}"#;
        assert_eq!(parse_github_latest(github).as_deref(), Some("0.5.1"));
    }

    #[test]
    fn cache_roundtrip_and_freshness() {
        let dir = std::env::temp_dir().join(format!(
            "ccc-update-cache-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = dir.join("update-check.json");
        let cache = UpdateCache {
            checked_at: 1000.0,
            current: "0.4.1".into(),
            latest: "0.5.0".into(),
            source: "crates.io".into(),
        };
        assert!(save_cache(&cache, &path));
        let loaded = load_cache(&path).expect("cache loads");
        assert_eq!(loaded.latest, "0.5.0");
        assert!(cache_is_fresh(&loaded, 24, 1000.0 + 10.0));
        assert!(!cache_is_fresh(&loaded, 24, 1000.0 + 90_000.0));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn format_notice_mentions_update_command() {
        let notice = format_update_notice("0.4.1", "0.5.0", false);
        assert!(notice.contains("0.5.0"));
        assert!(notice.contains("cargo install ccc"));
        let auto = format_update_notice("0.4.1", "0.5.0", true);
        assert!(auto.contains("background update"));
    }
}

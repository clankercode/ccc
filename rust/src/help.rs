use crate::config::load_config;
use crate::json_output::resolve_human_tty;
use crate::parser::AliasDef;
use crate::RUNNER_REGISTRY;
use serde_json::Value;
use std::fs;
use std::io::{self, IsTerminal, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

struct RunnerStatus {
    binary: String,
    found: bool,
    version: String,
    elapsed: Option<Duration>,
}

const CANONICAL_RUNNERS: &[(&str, &str)] = &[
    ("opencode", "oc"),
    ("claude", "cc"),
    ("kimi", "k"),
    ("codex", "c/cx"),
    ("roocode", "rc"),
    ("crush", "cr"),
    ("cursor", "cu"),
    ("gemini", "g"),
    ("pi", "p"),
    ("grok", "gb"),
];

const HELP_TEXT: &str = r#"ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc config
  ccc config --edit [--user|--local]
  ccc add [-g] <alias>
  ccc --print-config
  ccc help
  ccc --help
  ccc -h
  ccc @reviewer --help

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr), cursor (cu), gemini (g), pi (p), grok (gb)
  +thinking     Set thinking level: +0..+6 or +none/+low/+med/+mid/+medium/+high/+xhigh/+max/+ultra
                Levels map 0 none, 1 low, 2 medium, 3 high, 4 xhigh, 5 max, 6 ultra
                Claude maps +0 to --thinking disabled and +1..+6 to --thinking enabled with matching --effort (capped at max)
                Kimi maps +0 to --no-thinking and +1..+6 to --thinking
                Codex maps each level to -c model_reasoning_effort (none/low/medium/high/xhigh/max/ultra)
                Runners with fewer effort levels clamp +6 down to their top level
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, runner names select runners before agent fallback
                Presets can also define a default prompt when the user leaves prompt text blank
                prompt_mode lets alias prompts prepend or append text; prepend/append require an explicit prompt argument
                fallback_models retries once per model after a capacity or overload error that happens before any assistant output. Mapped models such as glm-5.3, llmp-glm-5-3, and glm-5.3-flash switch to grok; other models stay on the same runner. JSON and formatted output from that retry is parsed with the fallback runner's schema. Authentication errors and failures after output has started do not fall back. Claude runners are not retried, and MiniMax, Claude, or Astra model ids are skipped.
  .mode / ..mode
                Output-mode sugar with a shared dot identity:
                  .text / ..text, .json / ..json, .fmt / ..fmt, .pt / ..pt, .pj / ..pj
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported
  --fast / --no-fast
                Select fast/default service tier (Codex: -c service_tier="fast"/"default");
                unsupported runners warn and ignore it
  --service-tier <default|fast|priority|ultrafast>
                Select the Codex service tier; CLI overrides alias and config defaults
  --standalone / --no-daemon / --no-standalone
                Request an explicit upstream daemon opt-out: codex --no-daemon exec ...;
                OpenCode uses opencode run --standalone. --no-standalone omits the option.
                Codex exec currently uses an in-process app-server; this cannot force shared daemon execution.
                Unsupported runners warn only when standalone is true.
  --save-session
                Allow the selected runner to save this run in its normal session history
  --cleanup-session
                Try to clean up the created session after the run when no no-persist flag exists

Flags:
  --print-config                         Print the canonical example config.toml and exit
  help / --help / -h                    Print help and exit, even when mixed with other args
  --version / -v                        Print the ccc version and resolved client versions
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: on; config key: show_thinking)
  --sanitize-osc / --no-sanitize-osc    Strip disruptive OSC control output in human-facing modes
                                        while preserving OSC 8 hyperlinks
                                        (config key: defaults.sanitize_osc)
  --output-log-path / --no-output-log-path
                                        Print the parseable run-artifact footer line on stderr
  --output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted|pass-text|pt|stream-pass-text|stream-pt|pass-json|pj|stream-pass-json|stream-pj>
                                        Select raw, streamed, or formatted output handling
                                        (config key: defaults.output_mode)
  --forward-unknown-json                In formatted modes, forward unhandled JSON objects to stderr
  --timeout-secs <N>                    Kill the runner after N seconds and exit 124
  --runner-arg <ARG>                    Append one raw argument to the resolved runner command before the prompt
  Environment:
    CCC_FWD_UNKNOWN_JSON                Also controls unknown-JSON forwarding; defaults on for now
    FORCE_COLOR / NO_COLOR              Override TTY detection for formatted human output
                                        (FORCE_COLOR wins if both are set)
    CCC_UPDATE_CHECK / CCC_AUTO_UPDATE    Override [update] check / auto_update after runs
    CCC_UPDATE_CACHE / CCC_UPDATE_INTERVAL_HOURS
                                        Override update cache path and re-check interval
  --            Treat all remaining args as prompt text, even if they look like controls

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc --permission-mode auto c "Add tests"
  ccc --yolo cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc --permission-mode plan k "Think before editing"
  ccc ..fmt cc +3 "Investigate the failing test"
  ccc -o stream-json k "Reply with exactly pong"
  ccc @reviewer k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"
  ccc c --fast "Write a unit test"
  ccc -y -- +1 @agent :model
  ccc --print-config

Config:
  ccc config                            — print every resolved config file path and contents
  ccc config --edit                     — open the selected config in $EDITOR
  ccc config --edit --user              — open XDG_CONFIG_HOME/ccc/config.toml or ~/.config/ccc/config.toml
  ccc config --edit --local             — open the nearest .ccc.toml, or create one in CWD
  ccc add [-g] <alias>                  — prompt for alias settings and write them to config
  ccc add <alias> --runner cc --prompt "Review" --yes
                                        — write an alias non-interactively
  ccc --print-config                    — print the canonical example config.toml
  .ccc.toml (searched upward from CWD)  — project-local presets and defaults
  XDG_CONFIG_HOME/ccc/config.toml       — global defaults when XDG is set
  ~/.config/ccc/config.toml             — legacy global fallback
  [update] check / auto_update / interval_hours
                                        — after each run, warn when a newer ccc is available;
                                          auto_update can background `cargo install ccc`

Agent tips:
  Run `ccc config` before relying on aliases or defaults; `ccc --help` lists the aliases visible from the current directory.
  Use `ccc @alias "task"` when an alias matches the job, then add explicit runner/model/thinking controls only when they matter.
  Use `--` before prompt text that starts with control-like tokens such as `+1`, `@agent`, or `:model`.
"#;

fn get_version(binary: &str) -> String {
    match Command::new(binary)
        .arg("--version")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .lines()
            .next()
            .unwrap_or("")
            .to_string(),
        _ => String::new(),
    }
}

fn ccc_version() -> String {
    option_env!("CCC_VERSION")
        .unwrap_or(env!("CARGO_PKG_VERSION"))
        .to_string()
}

fn read_json_version(package_json_path: &Path, expected_name: &str) -> String {
    let payload = match fs::read_to_string(package_json_path) {
        Ok(text) => text,
        Err(_) => return String::new(),
    };
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return String::new(),
    };
    if parsed.get("name").and_then(Value::as_str) != Some(expected_name) {
        return String::new();
    }
    parsed
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn discover_opencode_version(binary_path: &Path) -> String {
    if binary_path.file_name().and_then(|name| name.to_str()) == Some("opencode-cli") {
        let version = read_prefix(&binary_path.with_file_name("opencode-cli.version"), 128);
        let version = version.trim();
        if valid_version_token(version) {
            return format!("opencode v{version}");
        }
    }
    node_package_version(binary_path, &["opencode-ai"])
}

fn discover_codex_version(binary_path: &Path) -> String {
    let version = node_package_version(binary_path, &["@openai/codex"]);
    if version.is_empty() {
        String::new()
    } else {
        format!("codex-cli {version}")
    }
}

fn read_prefix(path: &Path, limit: u64) -> String {
    let Ok(file) = fs::File::open(path) else {
        return String::new();
    };
    let mut bytes = Vec::new();
    if file.take(limit).read_to_end(&mut bytes).is_err() {
        return String::new();
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

fn valid_version_token(version: &str) -> bool {
    version.as_bytes().first().is_some_and(u8::is_ascii_digit)
        && version
            .bytes()
            .all(|ch| ch.is_ascii_alphanumeric() || b"._+-".contains(&ch))
}

fn launcher_paths(path: &Path) -> Vec<PathBuf> {
    let launcher = read_prefix(path, 16384);
    if !launcher.starts_with("#!") {
        return Vec::new();
    }
    let home = std::env::var("HOME").unwrap_or_default();
    let basedir = path.parent().unwrap_or(path).to_string_lossy();
    let mut paths = Vec::new();
    // Only expand known literal path variables. Never evaluate shell code.
    for token in launcher.split(['\'', '"']).skip(1).step_by(2) {
        let mut token = token.to_string();
        for (variable, value) in [
            ("HOME", home.as_str()),
            ("basedir", &basedir),
            ("SCRIPT_DIR", &basedir),
        ] {
            token = token.replace(&format!("${{{variable}}}"), value);
            token = token.replace(&format!("${variable}/"), &format!("{value}/"));
        }
        if token.starts_with("~/") && !home.is_empty() {
            token = format!("{home}{}", &token[1..]);
        }
        if token.contains(['$', '`', '\n']) || !Path::new(&token).is_absolute() {
            continue;
        }
        if let Ok(candidate) = fs::canonicalize(token) {
            if candidate.is_file() && !paths.contains(&candidate) {
                paths.push(candidate);
            }
        }
    }
    paths
}

fn node_package_version(binary_path: &Path, names: &[&str]) -> String {
    let candidates = std::iter::once(binary_path.to_path_buf()).chain(launcher_paths(binary_path));
    for candidate in candidates {
        for parent in candidate.ancestors().skip(1).take(6) {
            for name in names {
                let version = read_json_version(&parent.join("package.json"), name);
                if !version.is_empty() {
                    return version;
                }
            }
        }
    }
    String::new()
}

fn discover_claude_version(binary_path: &Path) -> String {
    let parts: Vec<_> = binary_path
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    if parts.len() < 3 || parts[parts.len() - 3] != "claude" || parts[parts.len() - 2] != "versions"
    {
        return String::new();
    }
    let version = &parts[parts.len() - 1];
    if version.is_empty() {
        String::new()
    } else {
        format!("{version} (Claude Code)")
    }
}

fn discover_kimi_version(binary_path: &Path) -> String {
    if binary_path
        .parent()
        .and_then(Path::file_name)
        .and_then(|value| value.to_str())
        != Some("bin")
    {
        return String::new();
    }
    if let Some(root) = binary_path.parent().and_then(Path::parent) {
        if let Ok(receipt) = fs::read_to_string(root.join("updates/install.json")) {
            if let Ok(receipt) = serde_json::from_str::<Value>(&receipt) {
                if let Some(version) = receipt
                    .get("lastSuccess")
                    .and_then(|installed| installed.get("version"))
                    .and_then(Value::as_str)
                    .filter(|version| valid_version_token(version))
                {
                    return version.to_string();
                }
            }
        }
    }
    let lib_dir = match binary_path.parent().and_then(Path::parent) {
        Some(parent) => parent.join("lib"),
        None => return String::new(),
    };
    let lib_entries = match fs::read_dir(&lib_dir) {
        Ok(entries) => entries,
        Err(_) => return String::new(),
    };
    for lib_entry in lib_entries.flatten() {
        let python_dir = lib_entry.path();
        let site_packages = python_dir.join("site-packages");
        let dist_entries = match fs::read_dir(&site_packages) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for dist_entry in dist_entries.flatten() {
            let dist_path = dist_entry.path();
            let Some(name) = dist_path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            if !name.starts_with("kimi_cli-") || !name.ends_with(".dist-info") {
                continue;
            }
            let metadata_path = dist_path.join("METADATA");
            let Ok(metadata) = fs::read_to_string(metadata_path) else {
                continue;
            };
            for line in metadata.lines() {
                if let Some(version) = line.strip_prefix("Version: ") {
                    if !version.trim().is_empty() {
                        return format!("kimi, version {}", version.trim());
                    }
                    return String::new();
                }
            }
        }
    }
    String::new()
}

fn json_name_matches(package_json_path: &Path, expected_name: &str) -> bool {
    let payload = match fs::read_to_string(package_json_path) {
        Ok(text) => text,
        Err(_) => return false,
    };
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return false,
    };
    parsed.get("name").and_then(Value::as_str) == Some(expected_name)
}

fn read_cursor_release_version(index_path: &Path) -> String {
    let Ok(mut file) = fs::File::open(index_path) else {
        return String::new();
    };
    let mut chunk = [0; 65536];
    let mut overlap = Vec::new();
    for _ in 0..256 {
        let Ok(count) = file.read(&mut chunk) else {
            break;
        };
        if count == 0 {
            break;
        }
        overlap.extend_from_slice(&chunk[..count]);
        let text = String::from_utf8_lossy(&overlap);
        for (start, marker) in text.match_indices("agent-cli@") {
            let tail = &text[start + marker.len()..];
            let version: String = tail
                .chars()
                .take_while(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
                .collect();
            if valid_version_token(&version) && version.len() < tail.len() {
                return version;
            }
        }
        for (start, _) in text.match_indices("option:version") {
            let tail = &text[start + "option:version".len()..];
            let tail = tail.get(..128).unwrap_or(tail);
            for quote in ["=\"", "='"] {
                if let Some(start) = tail.find(quote) {
                    let value = &tail[start + 2..];
                    if let Some(end) = value.find(quote.chars().nth(1).unwrap()) {
                        if valid_version_token(&value[..end]) {
                            return value[..end].to_string();
                        }
                    }
                }
            }
        }
        if overlap.len() > 512 {
            overlap.drain(..overlap.len() - 512);
        }
    }
    String::new()
}

fn elf_number(bytes: &[u8], offset: usize, width: usize, little: bool) -> Option<u64> {
    let field = bytes.get(offset..offset.checked_add(width)?)?;
    Some(field.iter().enumerate().fold(0, |value, (i, byte)| {
        value | (u64::from(*byte) << (8 * if little { i } else { width - 1 - i }))
    }))
}

fn read_at(file: &mut fs::File, offset: u64, size: u64) -> Option<Vec<u8>> {
    if size > 1_048_576 {
        return None;
    }
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut bytes = vec![0; size as usize];
    file.read_exact(&mut bytes).ok()?;
    Some(bytes)
}

fn crush_elf_version(binary_path: &Path) -> Option<String> {
    let mut file = fs::File::open(binary_path).ok()?;
    let header = read_at(&mut file, 0, 64)?;
    if &header[..4] != b"\x7fELF" || ![1, 2].contains(&header[4]) || ![1, 2].contains(&header[5]) {
        return None;
    }
    let wide = header[4] == 2;
    let little = header[5] == 1;
    let width = if wide { 8 } else { 4 };
    let offset = elf_number(&header, if wide { 40 } else { 32 }, width, little)?;
    let index = if wide { 58 } else { 46 };
    let size = elf_number(&header, index, 2, little)? as usize;
    let count = elf_number(&header, index + 2, 2, little)? as usize;
    let names_index = elf_number(&header, index + 4, 2, little)? as usize;
    if size < (if wide { 64 } else { 40 })
        || size > 256
        || count == 0
        || count > 4096
        || names_index >= count
    {
        return None;
    }
    let table = read_at(&mut file, offset, (size * count) as u64)?;
    let section_data = |section: &[u8]| -> Option<(u64, u64)> {
        let index = if wide { 24 } else { 16 };
        Some((
            elf_number(section, index, width, little)?,
            elf_number(section, index + width, width, little)?,
        ))
    };
    let (names_offset, names_size) = section_data(&table[names_index * size..][..size])?;
    let names = read_at(&mut file, names_offset, names_size)?;
    for section in table.chunks_exact(size) {
        let name = elf_number(section, 0, 4, little)? as usize;
        let Some(name) = names.get(name..) else {
            continue;
        };
        if name.split(|byte| *byte == 0).next() != Some(b".go.buildinfo".as_slice()) {
            continue;
        }
        let (offset, size) = section_data(section)?;
        let data = read_at(&mut file, offset, size)?;
        if !data.starts_with(b"\xff Go buildinf:") {
            return None;
        }
        let text = String::from_utf8_lossy(&data);
        for line in text.lines() {
            if let Some(version) = line.strip_prefix("mod\tgithub.com/charmbracelet/crush\t") {
                let version = version.split('\t').next()?;
                if version.starts_with('v') && valid_version_token(&version[1..]) {
                    return Some(format!("crush version {version}"));
                }
            }
        }
    }
    None
}

fn discover_cursor_version(binary_path: &Path) -> String {
    let package_root = binary_path.parent().unwrap_or(binary_path);
    if !json_name_matches(
        &package_root.join("package.json"),
        "@anysphere/agent-cli-runtime",
    ) {
        return String::new();
    }
    read_cursor_release_version(&package_root.join("index.js"))
}

fn discover_gemini_version(binary_path: &Path) -> String {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    discover_gemini_version_with_home(binary_path, home.as_deref())
}

fn discover_gemini_version_with_home(binary_path: &Path, home: Option<&Path>) -> String {
    let mut candidates = vec![
        binary_path
            .parent()
            .unwrap_or(binary_path)
            .join("package.json"),
        binary_path
            .parent()
            .unwrap_or(binary_path)
            .parent()
            .unwrap_or(binary_path)
            .join("package.json"),
    ];
    let mut is_npx_launcher = false;
    {
        let launcher = read_prefix(binary_path, 16384);
        if launcher.contains("@google/gemini-cli") {
            is_npx_launcher = true;
            if let Some(home) = home {
                let npx_root = home.join(".npm").join("_npx");
                if let Ok(entries) = fs::read_dir(npx_root) {
                    for entry in entries.flatten() {
                        candidates.push(
                            entry
                                .path()
                                .join("node_modules")
                                .join("@google")
                                .join("gemini-cli")
                                .join("package.json"),
                        );
                    }
                }
            }
        }
    }
    for candidate in candidates {
        let version = read_json_version(&candidate, "@google/gemini-cli");
        if !version.is_empty() {
            return version;
        }
    }
    if is_npx_launcher {
        return "npx @google/gemini-cli".to_string();
    }
    String::new()
}

fn discover_grok_version(_binary_path: &Path) -> String {
    let grok_home = std::env::var_os("GROK_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".grok")));
    let Some(grok_home) = grok_home else {
        return String::new();
    };
    let version_json = grok_home.join("version.json");
    let Ok(text) = fs::read_to_string(version_json) else {
        return String::new();
    };
    let Ok(payload) = serde_json::from_str::<Value>(&text) else {
        return String::new();
    };
    payload
        .get("version")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(|v| format!("grok {v}"))
        .unwrap_or_default()
}

fn get_runner_version(runner_name: &str, binary: &str, binary_path: &Path) -> String {
    let real_path = match fs::canonicalize(binary_path) {
        Ok(path) => path,
        Err(_) => binary_path.to_path_buf(),
    };
    let version = match runner_name {
        "opencode" => discover_opencode_version(&real_path),
        "codex" => discover_codex_version(&real_path),
        "claude" => discover_claude_version(&real_path),
        "kimi" => discover_kimi_version(&real_path),
        "cursor" => discover_cursor_version(&real_path),
        "gemini" => discover_gemini_version(&real_path),
        "grok" => discover_grok_version(&real_path),
        "pi" => node_package_version(
            &real_path,
            &[
                "@earendil-works/pi-coding-agent",
                "@mariozechner/pi-coding-agent",
            ],
        ),
        "crush" => crush_elf_version(&real_path).unwrap_or_default(),
        _ => String::new(),
    };
    if version.is_empty() {
        get_version(binary)
    } else {
        version
    }
}

fn resolve_binary_path(binary: &str) -> Option<String> {
    let executable = |path: &Path| {
        let Ok(metadata) = fs::metadata(path) else {
            return false;
        };
        if !metadata.is_file() {
            return false;
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            metadata.permissions().mode() & 0o111 != 0
        }
        #[cfg(not(unix))]
        {
            true
        }
    };
    if Path::new(binary).components().count() > 1 {
        return executable(Path::new(binary)).then(|| binary.to_string());
    }
    let path = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(binary);
        if executable(&candidate) {
            return Some(candidate.to_string_lossy().into_owned());
        }
        #[cfg(windows)]
        for extension in std::env::var("PATHEXT")
            .unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into())
            .split(';')
        {
            let candidate = directory.join(format!("{binary}{extension}"));
            if executable(&candidate) {
                return Some(candidate.to_string_lossy().into_owned());
            }
        }
    }
    None
}

fn runner_checklist() -> Vec<RunnerStatus> {
    let mut statuses = Vec::new();
    for &(name, _) in CANONICAL_RUNNERS {
        let registry = RUNNER_REGISTRY.read().unwrap();
        let binary = registry
            .get(name)
            .map(|info| info.binary.clone())
            .unwrap_or_else(|| name.to_string());
        drop(registry);

        let binary_path = resolve_binary_path(&binary);
        let found = binary_path.is_some();
        let (version, elapsed) = if let Some(path) = binary_path {
            let started = Instant::now();
            let version = get_runner_version(name, &binary, Path::new(&path));
            (version, Some(started.elapsed()))
        } else {
            (String::new(), None)
        };
        statuses.push(RunnerStatus {
            binary,
            found,
            version,
            elapsed,
        });
    }
    statuses
}

fn format_elapsed(elapsed: Option<Duration>, color: bool) -> String {
    let text = elapsed
        .map(|elapsed| format!("{:.1} ms", elapsed.as_secs_f64() * 1000.0))
        .unwrap_or_else(|| "-".to_string());
    if color && elapsed.is_some_and(|elapsed| elapsed > Duration::from_millis(50)) {
        format!("\x1b[31m{text}\x1b[0m")
    } else {
        text
    }
}

fn format_runner_rows<'a>(
    statuses: impl IntoIterator<Item = &'a RunnerStatus>,
    color: bool,
) -> String {
    let rows: Vec<_> = statuses
        .into_iter()
        .map(|status| {
            let tag = if !status.found {
                "not found"
            } else if status.version.is_empty() {
                "found"
            } else {
                &status.version
            };
            (status, tag)
        })
        .collect();
    let binary_width = rows
        .iter()
        .map(|(status, _)| status.binary.chars().count())
        .max()
        .unwrap_or(0);
    let version_width = rows
        .iter()
        .map(|(_, tag)| tag.chars().count())
        .max()
        .unwrap_or(0);
    let mut out = String::new();
    for (status, tag) in rows {
        let marker = if status.found { '+' } else { '-' };
        let elapsed = format_elapsed(status.elapsed, color);
        out.push_str(&format!(
            "  [{marker}] {:binary_width$}  {tag:version_width$}  {elapsed}\n",
            status.binary
        ));
    }
    out
}

fn runner_color_enabled(is_terminal: bool) -> bool {
    resolve_human_tty(
        is_terminal,
        std::env::var("FORCE_COLOR").ok().as_deref(),
        std::env::var("NO_COLOR").ok().as_deref(),
    )
}

fn format_runner_checklist(color: bool) -> String {
    let mut out = String::from("Runners:\n");
    out.push_str(&format_runner_rows(&runner_checklist(), color));
    out
}

fn format_alias_value(value: &str) -> String {
    let text = value.replace(['\r', '\n'], " ");
    if text
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | ':' | '/' | '+' | '-'))
    {
        return text;
    }
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

fn format_alias_summary(alias: &AliasDef) -> String {
    let mut fields = Vec::new();
    if let Some(value) = &alias.runner {
        fields.push(format!("runner={}", format_alias_value(value)));
    }
    if let Some(value) = &alias.provider {
        fields.push(format!("provider={}", format_alias_value(value)));
    }
    if let Some(value) = &alias.model {
        fields.push(format!("model={}", format_alias_value(value)));
    }
    if let Some(value) = alias.thinking {
        fields.push(format!("thinking={value}"));
    }
    if let Some(value) = alias.show_thinking {
        fields.push(format!(
            "show_thinking={}",
            if value { "true" } else { "false" }
        ));
    }
    if let Some(value) = alias.sanitize_osc {
        fields.push(format!(
            "sanitize_osc={}",
            if value { "true" } else { "false" }
        ));
    }
    if let Some(value) = &alias.output_mode {
        fields.push(format!("output_mode={}", format_alias_value(value)));
    }
    if let Some(value) = &alias.service_tier {
        fields.push(format!("service_tier={}", format_alias_value(value)));
    }
    if let Some(value) = alias.standalone {
        fields.push(format!("standalone={value}"));
    }
    if let Some(value) = &alias.agent {
        fields.push(format!("agent={}", format_alias_value(value)));
    }
    if let Some(value) = &alias.prompt {
        fields.push(format!("prompt={}", format_alias_value(value)));
    }
    if let Some(value) = &alias.prompt_mode {
        fields.push(format!("prompt_mode={}", format_alias_value(value)));
    }
    if let Some(models) = &alias.fallback_models {
        if !models.is_empty() {
            fields.push(format!("fallback_models={}", models.join(",")));
        }
    }
    if fields.is_empty() {
        "(empty)".to_string()
    } else {
        fields.join(" ")
    }
}

fn format_alias_checklist() -> String {
    let config = load_config(None);
    let mut out = String::from("Configured aliases:\n");
    if config.aliases.is_empty() {
        out.push_str("  (none)\n");
        return out;
    }
    for (name, alias) in config.aliases {
        out.push_str(&format!("  @{name:<11} {}\n", format_alias_summary(&alias)));
    }
    out
}

fn format_version_report(version: &str, statuses: &[RunnerStatus], color: bool) -> String {
    let mut out = format!("ccc version {version}\nResolved clients:\n");
    let resolved_statuses: Vec<_> = statuses.iter().filter(|s| !s.version.is_empty()).collect();
    let resolved = resolved_statuses.len();
    out.push_str(&format_runner_rows(resolved_statuses, color));
    let unresolved = statuses.len().saturating_sub(resolved);
    if unresolved > 0 {
        out.push_str(&format!("  (and {unresolved} unresolved)\n"));
    }
    out.trim_end_matches('\n').to_string()
}

pub fn print_help() {
    print!("{}", HELP_TEXT);
    println!();
    println!("{}", format_alias_checklist().trim_end());
    println!();
    print!(
        "{}",
        format_runner_checklist(runner_color_enabled(io::stdout().is_terminal()))
    );
}

pub fn print_version() {
    println!(
        "{}",
        format_version_report(
            &ccc_version(),
            &runner_checklist(),
            runner_color_enabled(io::stdout().is_terminal()),
        )
    );
}

pub fn print_usage() {
    eprintln!("usage: ccc [controls...] \"<Prompt>\"");
    eprint!(
        "{}",
        format_runner_checklist(runner_color_enabled(io::stderr().is_terminal()))
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("ccc-help-{label}-{unique}"));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn test_elapsed_color_uses_unrounded_strict_threshold() {
        let threshold = Duration::from_millis(50);
        let just_above = Duration::from_micros(50_010);
        assert_eq!(
            format_elapsed(Some(Duration::from_micros(49_990)), true),
            "50.0 ms"
        );
        assert_eq!(format_elapsed(Some(threshold), true), "50.0 ms");
        assert_eq!(
            format_elapsed(Some(just_above), true),
            "\x1b[31m50.0 ms\x1b[0m"
        );
        assert_eq!(format_elapsed(Some(just_above), false), "50.0 ms");
        assert_eq!(format_elapsed(None, true), "-");
    }

    #[test]
    fn test_get_runner_version_reads_opencode_package_json_before_command() {
        let root = unique_temp_dir("opencode");
        let package_root = root.join("node_modules").join("opencode-ai");
        let binary_path = package_root.join("bin").join("opencode");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"opencode-ai","version":"1.2.3"}"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/bin/sh\nexit 99\n").unwrap();

        assert_eq!(
            get_runner_version("opencode", "definitely-missing-binary", &binary_path),
            "1.2.3"
        );
    }

    #[test]
    fn test_get_runner_version_reads_codex_package_json_before_command() {
        let root = unique_temp_dir("codex");
        let package_root = root.join("node_modules").join("@openai").join("codex");
        let binary_path = package_root.join("bin").join("codex.js");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"@openai/codex","version":"0.118.0"}"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/usr/bin/env node\n").unwrap();

        assert_eq!(
            get_runner_version("codex", "definitely-missing-binary", &binary_path),
            "codex-cli 0.118.0"
        );
    }

    #[test]
    fn test_get_runner_version_reads_claude_version_from_install_path() {
        let root = unique_temp_dir("claude");
        let versions_dir = root.join("claude").join("versions");
        fs::create_dir_all(&versions_dir).unwrap();
        let binary_path = versions_dir.join("2.1.98");
        fs::write(&binary_path, "").unwrap();

        assert_eq!(
            get_runner_version("claude", "definitely-missing-binary", &binary_path),
            "2.1.98 (Claude Code)"
        );
    }

    #[test]
    fn test_get_runner_version_reads_kimi_metadata_before_command() {
        let root = unique_temp_dir("kimi");
        let binary_path = root.join("bin").join("kimi");
        let metadata_dir = root
            .join("lib")
            .join("python3.13")
            .join("site-packages")
            .join("kimi_cli-1.30.0.dist-info");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::create_dir_all(&metadata_dir).unwrap();
        fs::write(&binary_path, "#!/usr/bin/env python3\n").unwrap();
        fs::write(
            metadata_dir.join("METADATA"),
            "Metadata-Version: 2.3\nName: kimi-cli\nVersion: 1.30.0\n",
        )
        .unwrap();

        assert_eq!(
            get_runner_version("kimi", "definitely-missing-binary", &binary_path),
            "kimi, version 1.30.0"
        );
    }

    #[test]
    fn test_get_runner_version_reads_cursor_release_marker_before_command() {
        let root = unique_temp_dir("cursor");
        let package_root = root.join("cursor-agent");
        let binary_path = package_root.join("cursor-agent");
        fs::create_dir_all(&package_root).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"@anysphere/agent-cli-runtime","private":true}"#,
        )
        .unwrap();
        fs::write(
            package_root.join("index.js"),
            r#"globalThis.SENTRY_RELEASE={id:"agent-cli@2026.03.30-a5d3e17"};"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/bin/sh\nexit 99\n").unwrap();

        assert_eq!(
            get_runner_version("cursor", "definitely-missing-binary", &binary_path),
            "2026.03.30-a5d3e17"
        );
    }

    #[test]
    fn test_get_runner_version_reads_gemini_package_json_before_command() {
        let root = unique_temp_dir("gemini");
        let package_root = root.join("node_modules").join("@google").join("gemini-cli");
        let binary_path = package_root.join("dist").join("index.js");
        fs::create_dir_all(binary_path.parent().unwrap()).unwrap();
        fs::write(
            package_root.join("package.json"),
            r#"{"name":"@google/gemini-cli","version":"0.37.2"}"#,
        )
        .unwrap();
        fs::write(&binary_path, "#!/usr/bin/env node\n").unwrap();

        assert_eq!(
            get_runner_version("gemini", "definitely-missing-binary", &binary_path),
            "0.37.2"
        );
    }

    #[test]
    fn test_get_runner_version_identifies_gemini_npx_launcher_without_command() {
        let root = unique_temp_dir("gemini-npx");
        let binary_path = root.join("gemini");
        fs::write(
            &binary_path,
            "#!/bin/bash\nexec npx --yes @google/gemini-cli \"$@\"\n",
        )
        .unwrap();

        assert_eq!(
            discover_gemini_version_with_home(&binary_path, Some(&root)),
            "npx @google/gemini-cli"
        );
    }

    #[test]
    fn test_get_runner_version_falls_back_when_metadata_is_missing() {
        assert_eq!(
            get_runner_version(
                "opencode",
                "definitely-missing-binary",
                Path::new("/tmp/missing/opencode")
            ),
            ""
        );
    }
}

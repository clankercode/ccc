use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static RUN_ID_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TranscriptKind {
    Text,
    Jsonl,
}

pub struct RunArtifacts {
    run_dir: PathBuf,
    output_path: PathBuf,
    transcript_path: PathBuf,
    transcript_warning: Option<String>,
    transcript: Mutex<Option<File>>,
}

impl RunArtifacts {
    pub fn create(transcript_kind: TranscriptKind) -> io::Result<Self> {
        Self::create_in(resolve_state_root(), transcript_kind)
    }

    pub fn create_for_runner(
        runner_name: &str,
        transcript_kind: TranscriptKind,
    ) -> io::Result<Self> {
        Self::create_in_for_runner(resolve_state_root(), transcript_kind, runner_name)
    }

    pub fn create_in(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
    ) -> io::Result<Self> {
        Self::create_in_with_id_source(state_root, transcript_kind, default_run_id)
    }

    pub fn create_in_for_runner(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        runner_name: &str,
    ) -> io::Result<Self> {
        Self::create_in_with_id_source_for_runner(
            state_root,
            transcript_kind,
            runner_name,
            default_run_id,
        )
    }

    pub fn create_in_with_id_source<F>(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        next_run_id: F,
    ) -> io::Result<Self>
    where
        F: FnMut() -> String,
    {
        Self::create_in_with_id_source_and_transcript_opener(
            state_root,
            transcript_kind,
            next_run_id,
            |path| {
                OpenOptions::new()
                    .create(true)
                    .truncate(true)
                    .write(true)
                    .open(path)
            },
        )
    }

    pub fn create_in_with_id_source_for_runner<F>(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        runner_name: &str,
        next_run_id: F,
    ) -> io::Result<Self>
    where
        F: FnMut() -> String,
    {
        Self::create_in_with_id_source_and_transcript_opener_for_runner(
            state_root,
            transcript_kind,
            runner_name,
            next_run_id,
            |path| {
                OpenOptions::new()
                    .create(true)
                    .truncate(true)
                    .write(true)
                    .open(path)
            },
        )
    }

    pub fn create_in_with_id_source_and_transcript_opener<F, O>(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        next_run_id: F,
        transcript_opener: O,
    ) -> io::Result<Self>
    where
        F: FnMut() -> String,
        O: FnOnce(&Path) -> io::Result<File>,
    {
        Self::create_in_with_id_source_and_transcript_opener_internal(
            state_root,
            transcript_kind,
            None,
            next_run_id,
            transcript_opener,
        )
    }

    pub fn create_in_with_id_source_and_transcript_opener_for_runner<F, O>(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        runner_name: &str,
        next_run_id: F,
        transcript_opener: O,
    ) -> io::Result<Self>
    where
        F: FnMut() -> String,
        O: FnOnce(&Path) -> io::Result<File>,
    {
        Self::create_in_with_id_source_and_transcript_opener_internal(
            state_root,
            transcript_kind,
            Some(canonical_run_dir_prefix(runner_name)),
            next_run_id,
            transcript_opener,
        )
    }

    fn create_in_with_id_source_and_transcript_opener_internal<F, O>(
        state_root: impl AsRef<Path>,
        transcript_kind: TranscriptKind,
        run_dir_prefix: Option<String>,
        mut next_run_id: F,
        transcript_opener: O,
    ) -> io::Result<Self>
    where
        F: FnMut() -> String,
        O: FnOnce(&Path) -> io::Result<File>,
    {
        let runs_root = state_root.as_ref().join("ccc/runs");
        fs::create_dir_all(&runs_root)?;
        let run_dir_prefix = run_dir_prefix
            .map(|value| canonical_run_dir_prefix(&value))
            .filter(|value| !value.is_empty());

        let run_dir = loop {
            let run_id = next_run_id();
            let candidate_name = match run_dir_prefix.as_deref() {
                Some(prefix) => format!("{prefix}-{run_id}"),
                None => run_id,
            };
            let candidate = runs_root.join(&candidate_name);
            match fs::create_dir(&candidate) {
                Ok(()) => break candidate,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        };

        let transcript_path = run_dir.join(match transcript_kind {
            TranscriptKind::Text => "transcript.txt",
            TranscriptKind::Jsonl => "transcript.jsonl",
        });
        let (transcript, transcript_warning) = match transcript_opener(&transcript_path) {
            Ok(file) => (Some(file), None),
            Err(error) => (
                None,
                Some(transcript_io_warning("create", &transcript_path, &error)),
            ),
        };

        Ok(Self {
            output_path: run_dir.join("output.txt"),
            transcript_path,
            transcript_warning,
            transcript: Mutex::new(transcript),
            run_dir,
        })
    }

    pub fn run_dir(&self) -> &Path {
        &self.run_dir
    }

    pub fn output_path(&self) -> &Path {
        &self.output_path
    }

    pub fn transcript_path(&self) -> &Path {
        &self.transcript_path
    }

    pub fn transcript_warning(&self) -> Option<&str> {
        self.transcript_warning.as_deref()
    }

    pub fn record_stdout(&self, text: &str) -> io::Result<()> {
        let mut guard = self.transcript.lock().unwrap();
        if let Some(file) = guard.as_mut() {
            if let Err(error) = file.write_all(text.as_bytes()).and_then(|_| file.flush()) {
                *guard = None;
                return Err(error);
            }
        }
        Ok(())
    }

    pub fn write_output_text(&self, text: &str) -> io::Result<()> {
        fs::write(&self.output_path, text)
    }

    pub fn footer_line(&self) -> String {
        format!(">> ccc:output-log >> {}", self.run_dir.display())
    }
}

fn canonical_run_dir_prefix(run_dir_prefix: &str) -> String {
    match run_dir_prefix.trim().to_ascii_lowercase().as_str() {
        "oc" | "opencode" => "opencode".to_string(),
        "cc" | "claude" => "claude".to_string(),
        "c" | "cx" | "codex" => "codex".to_string(),
        "k" | "kimi" => "kimi".to_string(),
        "cr" | "crush" => "crush".to_string(),
        "rc" | "roocode" => "roocode".to_string(),
        "cu" | "cursor" => "cursor".to_string(),
        "g" | "gemini" => "gemini".to_string(),
        other => other.to_string(),
    }
}

pub fn output_write_warning(error: &io::Error) -> String {
    format!("warning: could not write output.txt: {error}")
}

pub fn transcript_io_warning(action: &str, transcript_path: &Path, error: &io::Error) -> String {
    let transcript_name = transcript_path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("transcript.txt");
    format!("warning: could not {action} {transcript_name}: {error}")
}

pub fn resolve_state_root() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        if let Some(local_app_data) = env_path("LOCALAPPDATA") {
            return local_app_data;
        }
        if let Some(home) = home_dir() {
            return home.join("AppData/Local");
        }
        return PathBuf::from(".");
    }

    #[cfg(target_os = "macos")]
    {
        if let Some(home) = home_dir() {
            return home.join("Library/Application Support");
        }
        return PathBuf::from(".");
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        if let Some(xdg_state_home) = env_path("XDG_STATE_HOME") {
            return xdg_state_home;
        }
        if let Some(home) = home_dir() {
            return home.join(".local/state");
        }
        PathBuf::from(".")
    }
}

fn env_path(key: &str) -> Option<PathBuf> {
    let value = env::var_os(key)?;
    if value.is_empty() {
        None
    } else {
        Some(PathBuf::from(value))
    }
}

fn home_dir() -> Option<PathBuf> {
    env_path("HOME")
}

fn default_run_id() -> String {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let pid = std::process::id();
    let sequence = RUN_ID_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("{timestamp}-{pid}-{sequence}")
}

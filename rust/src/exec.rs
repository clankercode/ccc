use std::collections::BTreeMap;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Clone, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub struct CommandSpec {
    pub argv: Vec<String>,
    pub stdin_text: Option<String>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<String, String>,
    pub timeout_secs: Option<u64>,
}

impl CommandSpec {
    pub fn new<I, S>(argv: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        Self {
            argv: argv.into_iter().map(Into::into).collect(),
            stdin_text: None,
            cwd: None,
            env: BTreeMap::new(),
            timeout_secs: None,
        }
    }

    pub fn with_stdin(mut self, stdin_text: impl Into<String>) -> Self {
        self.stdin_text = Some(stdin_text.into());
        self
    }

    pub fn with_cwd(mut self, cwd: impl Into<PathBuf>) -> Self {
        self.cwd = Some(cwd.into());
        self
    }

    pub fn with_env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.env.insert(key.into(), value.into());
        self
    }

    pub fn with_timeout_secs(mut self, secs: u64) -> Self {
        self.timeout_secs = Some(secs);
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub struct CompletedRun {
    pub argv: Vec<String>,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

impl CompletedRun {
    pub fn new(
        argv: Vec<String>,
        exit_code: i32,
        stdout: impl Into<String>,
        stderr: impl Into<String>,
    ) -> Self {
        Self {
            argv,
            exit_code,
            stdout: stdout.into(),
            stderr: stderr.into(),
            timed_out: false,
        }
    }

    pub fn with_timed_out(mut self, timed_out: bool) -> Self {
        self.timed_out = timed_out;
        self
    }
}

type StreamCallback = Arc<Mutex<dyn FnMut(&str, &str) + Send>>;
type RunExecutor = dyn Fn(CommandSpec) -> CompletedRun + Send + Sync;
type StreamExecutor = dyn Fn(CommandSpec, StreamCallback) -> CompletedRun + Send + Sync;

pub struct Runner {
    executor: Box<RunExecutor>,
    stream_executor: Box<StreamExecutor>,
}

impl Runner {
    pub fn new() -> Self {
        Self {
            executor: Box::new(default_run_executor),
            stream_executor: Box::new(default_stream_executor),
        }
    }

    pub fn with_executor(executor: Box<RunExecutor>) -> Self {
        Self {
            executor,
            stream_executor: Box::new(default_stream_executor),
        }
    }

    pub fn with_stream_executor(stream_executor: Box<StreamExecutor>) -> Self {
        Self {
            executor: Box::new(default_run_executor),
            stream_executor,
        }
    }

    pub fn run(&self, spec: CommandSpec) -> CompletedRun {
        if spec.timeout_secs.is_some() {
            return self.stream(spec, |_, _| {});
        }
        (self.executor)(spec)
    }

    pub fn stream<F>(&self, spec: CommandSpec, on_event: F) -> CompletedRun
    where
        F: FnMut(&str, &str) + Send + 'static,
    {
        (self.stream_executor)(spec, Arc::new(Mutex::new(on_event)))
    }
}

impl Default for Runner {
    fn default() -> Self {
        Self::new()
    }
}

pub fn build_prompt_spec(prompt: &str) -> Result<CommandSpec, &'static str> {
    let normalized_prompt = prompt.trim();
    if normalized_prompt.is_empty() {
        return Err("prompt must not be empty");
    }
    Ok(CommandSpec::new(["opencode", "run", normalized_prompt]))
}

fn default_run_executor(spec: CommandSpec) -> CompletedRun {
    let mut command = build_command(&spec);
    let output = command
        .output()
        .unwrap_or_else(|error| failed_output(&spec, error));
    CompletedRun {
        argv: spec.argv,
        exit_code: output.status.code().unwrap_or(1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        timed_out: false,
    }
}

fn default_stream_executor(spec: CommandSpec, callback: StreamCallback) -> CompletedRun {
    let argv = spec.argv.clone();
    let timeout = spec.timeout_secs;
    let mut command = build_command(&spec);
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let error_msg = format!(
                "failed to start {}: {}",
                spec.argv.first().map(|s| s.as_str()).unwrap_or("(unknown)"),
                error
            );
            if let Ok(mut cb) = callback.lock() {
                cb("stderr", &error_msg);
            }
            return CompletedRun {
                argv,
                exit_code: 1,
                stdout: String::new(),
                stderr: error_msg,
                timed_out: false,
            };
        }
    };

    if let Some(stdin_text) = &spec.stdin_text {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(stdin_text.as_bytes());
        }
    }

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();

    let cb_out = Arc::clone(&callback);
    let stdout_thread = thread::spawn(move || {
        let mut buf = String::new();
        if let Some(pipe) = stdout_pipe {
            use std::io::BufRead;
            let reader = std::io::BufReader::new(pipe);
            for line in reader.lines() {
                match line {
                    Ok(text) => {
                        buf.push_str(&text);
                        buf.push('\n');
                        let chunk = format!("{text}\n");
                        if let Ok(mut cb) = cb_out.lock() {
                            cb("stdout", &chunk);
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        buf
    });

    let cb_err = Arc::clone(&callback);
    let stderr_thread = thread::spawn(move || {
        let mut buf = String::new();
        if let Some(pipe) = stderr_pipe {
            use std::io::BufRead;
            let reader = std::io::BufReader::new(pipe);
            for line in reader.lines() {
                match line {
                    Ok(text) => {
                        buf.push_str(&text);
                        buf.push('\n');
                        let chunk = format!("{text}\n");
                        if let Ok(mut cb) = cb_err.lock() {
                            cb("stderr", &chunk);
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        buf
    });

    let timed_out_flag = Arc::new(AtomicBool::new(false));
    let watchdog_stop = Arc::new(AtomicBool::new(false));
    let child_handle = Arc::new(Mutex::new(child));
    let watchdog_handle = timeout.map(|secs| {
        let child_arc = Arc::clone(&child_handle);
        let flag = Arc::clone(&timed_out_flag);
        let stop = Arc::clone(&watchdog_stop);
        thread::spawn(move || watchdog_run(secs, child_arc, flag, stop))
    });

    let stdout_buf = stdout_thread.join().unwrap_or_default();
    let stderr_buf = stderr_thread.join().unwrap_or_default();

    watchdog_stop.store(true, Ordering::SeqCst);
    if let Some(handle) = watchdog_handle {
        let _ = handle.join();
    }

    let status = {
        let mut guard = child_handle.lock().unwrap();
        guard.wait().unwrap_or_else(|error| {
            exit_status_from_code(failed_output(&spec, error).status.code().unwrap_or(1))
        })
    };

    CompletedRun {
        argv,
        exit_code: status.code().unwrap_or(1),
        stdout: stdout_buf,
        stderr: stderr_buf,
        timed_out: timed_out_flag.load(Ordering::SeqCst),
    }
}

fn watchdog_run(
    secs: u64,
    child: Arc<Mutex<std::process::Child>>,
    timed_out: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
) {
    let deadline = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < deadline {
        if stop.load(Ordering::SeqCst) {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }
    if stop.load(Ordering::SeqCst) {
        return;
    }
    let mut guard = child.lock().unwrap();
    if matches!(guard.try_wait(), Ok(None)) {
        timed_out.store(true, Ordering::SeqCst);
        let _ = guard.kill();
    }
}

fn build_command(spec: &CommandSpec) -> Command {
    let mut argv = spec.argv.iter();
    let program = argv.next().cloned().unwrap_or_default();
    let mut command = Command::new(program);
    command.args(argv);
    if let Some(cwd) = &spec.cwd {
        command.current_dir(cwd);
    }
    command.envs(&spec.env);
    command.stdin(if spec.stdin_text.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    command
}

fn failed_output(spec: &CommandSpec, error: io::Error) -> std::process::Output {
    let stderr = format!(
        "failed to start {}: {}",
        spec.argv.first().map(|s| s.as_str()).unwrap_or("(unknown)"),
        error
    )
    .into_bytes();
    std::process::Output {
        status: exit_status_from_code(1),
        stdout: Vec::new(),
        stderr,
    }
}

#[cfg(unix)]
fn exit_status_from_code(code: i32) -> std::process::ExitStatus {
    std::process::ExitStatus::from_raw(code << 8)
}

#[cfg(windows)]
fn exit_status_from_code(code: i32) -> std::process::ExitStatus {
    std::process::ExitStatus::from_raw(code as u32)
}

#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;

#[cfg(windows)]
use std::os::windows::process::ExitStatusExt;

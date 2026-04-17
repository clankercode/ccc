# Rust API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a typed, idiomatic Rust library API for `ccc`, expose a compatibility sugar parser for `ccc`-style tokens, and improve docs.rs/library documentation without breaking the existing CLI surface.

**Architecture:** Build a new typed library layer inside the existing Rust crate, then migrate the CLI to consume that layer instead of exposing parser and rendering internals as the main API. Keep subprocess plumbing available as an explicit lower-level escape hatch, and keep sugar parsing as a clearly secondary compatibility module that resolves into the same typed request pipeline.

**Tech Stack:** Rust 2021, existing `cargo test` suite, the current `parser`, `json_output`, `config`, and `artifacts` modules, targeted cross-implementation contract checks, and docs.rs-focused crate docs in `rust/src/lib.rs` and `rust/README.md`.

---

## File Structure

Planned file ownership and responsibilities:

- Create: `rust/src/exec.rs`
  - Own low-level subprocess types migrated from `lib.rs`: `CommandSpec`, `CompletedRun`, and the execution backend.
- Create: `rust/src/invoke/mod.rs`
  - Re-export the typed library API entry points.
- Create: `rust/src/invoke/request.rs`
  - Define `Client`, `Request`, enums such as `RunnerKind` and `OutputMode`, and request-building logic.
- Create: `rust/src/invoke/plan.rs`
  - Define `Plan`, `Run`, `Warning`, and typed planning/execution helpers.
- Create: `rust/src/output/mod.rs`
  - Curate typed output exports.
- Create: `rust/src/output/model.rs`
  - Define typed transcript/event structures.
- Create: `rust/src/output/parse.rs`
  - Adapt existing structured-output parsing into typed transcript builders.
- Create: `rust/src/output/render.rs`
  - Keep human-rendering helpers used by the CLI.
- Create: `rust/src/sugar.rs`
  - Parse `ccc`-style sugar into typed `Request` values.
- Modify: `rust/src/lib.rs`
  - Re-export the new primary API, add crate docs, and de-emphasize internals.
- Modify: `rust/src/parser.rs`
  - Reuse internal resolution logic behind the new typed path and support the sugar module.
- Modify: `rust/src/json_output.rs`
  - Either become a compatibility shim or move internal logic into `output/*`.
- Modify: `rust/src/config.rs`
  - Support explicit typed config loading paths cleanly.
- Modify: `rust/src/bin/ccc.rs`
  - Consume the typed API and sugar parser instead of wiring directly through current public internals.
- Modify: `rust/Cargo.toml`
  - Add docs.rs metadata and keep crate metadata polished.
- Modify: `rust/README.md`
  - Rewrite library examples around the new typed API.
- Create or Modify: `rust/tests/library_api_tests.rs`
  - Add focused tests for the new Rust-only typed API.
- Modify: `rust/tests/parser_tests.rs`
  - Keep sugar parsing and CLI token compatibility covered.
- Modify: `rust/tests/json_output_tests.rs`
  - Keep structured parsing correct through the typed transcript layer.
- Modify: `rust/tests/help_tests.rs`
  - Keep CLI help/version behavior intact if public re-exports move.
- Modify: `tests/test_ccc_contract_impl.py`
  - Update only if CLI behavior changes materially during migration.
- Create: `CHANGELOG.md`
  - Backfill release notes for `0.1.1` and `0.1.2` if still missing when docs are updated.

### Task 1: Introduce the Typed Invocation Surface

**Files:**
- Create: `rust/src/exec.rs`
- Create: `rust/src/invoke/mod.rs`
- Create: `rust/src/invoke/request.rs`
- Create: `rust/src/invoke/plan.rs`
- Modify: `rust/src/lib.rs`
- Create: `rust/tests/library_api_tests.rs`

- [ ] **Step 1: Write the failing Rust library API tests**

```rust
use call_coding_clis::{Client, OutputMode, Request, RunnerKind};

#[test]
fn request_builder_sets_expected_fields() {
    let request = Request::new("review this patch")
        .runner(RunnerKind::Codex)
        .model("gpt-5.4-mini")
        .output_mode(OutputMode::StreamFormatted);

    assert_eq!(request.prompt(), "review this patch");
    assert_eq!(request.runner(), Some(RunnerKind::Codex));
    assert_eq!(request.model(), Some("gpt-5.4-mini"));
    assert_eq!(request.output_mode(), Some(OutputMode::StreamFormatted));
}

#[test]
fn client_plan_resolves_to_non_empty_command_spec() {
    let client = Client::new();
    let request = Request::new("explain this module").runner(RunnerKind::OpenCode);
    let plan = client.plan(&request).expect("plan should resolve");

    assert!(!plan.command_spec().argv.is_empty());
    assert_eq!(plan.runner(), RunnerKind::OpenCode);
}
```

Run: `cd rust && cargo test library_api_tests -- --nocapture`

Expected: compile errors for missing `Client`, `Request`, `RunnerKind`, `OutputMode`, or planning methods.

- [ ] **Step 2: Move execution primitives into `exec.rs` and add the new typed API skeleton**

```rust
// rust/src/exec.rs
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandSpec { /* moved from lib.rs */ }

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompletedRun { /* moved from lib.rs */ }

pub struct Runner { /* moved from lib.rs */ }
```

```rust
// rust/src/invoke/request.rs
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunnerKind {
    OpenCode,
    Claude,
    Codex,
    Kimi,
    Cursor,
    Gemini,
    RooCode,
    Crush,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputMode {
    Text,
    StreamText,
    Json,
    StreamJson,
    Formatted,
    StreamFormatted,
}

pub struct Request {
    prompt: String,
    runner: Option<RunnerKind>,
    model: Option<String>,
    output_mode: Option<OutputMode>,
}
```

```rust
// rust/src/invoke/plan.rs
pub struct Plan {
    command_spec: CommandSpec,
    runner: RunnerKind,
    output_mode: OutputMode,
    warnings: Vec<String>,
}

pub struct Client;
```

- [ ] **Step 3: Implement the minimum planning path by adapting existing parser resolution**

```rust
impl Client {
    pub fn new() -> Self {
        Self
    }

    pub fn plan(&self, request: &Request) -> Result<Plan, Error> {
        let argv = request.to_cli_tokens();
        let parsed = crate::parser::parse_args(&argv);
        let config = crate::config::load_config(None);
        let (argv, env, warnings) = crate::parser::resolve_command(&parsed, Some(&config))?;
        let output_mode = request.output_mode.unwrap_or(OutputMode::Text);
        let runner = request.runner.unwrap_or(RunnerKind::OpenCode);
        Ok(Plan {
            command_spec: CommandSpec { argv, stdin_text: None, cwd: None, env },
            runner,
            output_mode,
            warnings,
        })
    }
}
```

The point of this step is not to finalize the architecture. It is to put the typed API in front of the existing internal semantics quickly so tests and docs can move onto the new surface.

- [ ] **Step 4: Re-run the focused Rust tests**

Run: `cd rust && cargo test library_api_tests -- --nocapture`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/src/exec.rs rust/src/invoke/mod.rs rust/src/invoke/request.rs rust/src/invoke/plan.rs rust/src/lib.rs rust/tests/library_api_tests.rs
git commit -m "Add typed Rust invocation API skeleton"
```

### Task 2: Add Typed Run, Error, and Output Models

**Files:**
- Create: `rust/src/output/mod.rs`
- Create: `rust/src/output/model.rs`
- Create: `rust/src/output/parse.rs`
- Create: `rust/src/output/render.rs`
- Modify: `rust/src/json_output.rs`
- Modify: `rust/src/invoke/plan.rs`
- Modify: `rust/src/lib.rs`
- Modify: `rust/tests/json_output_tests.rs`
- Modify: `rust/tests/library_api_tests.rs`

- [ ] **Step 1: Write the failing transcript and run tests**

```rust
use call_coding_clis::{Event, Transcript};

#[test]
fn typed_transcript_preserves_final_text_and_unknown_json() {
    let transcript = Transcript {
        events: vec![Event::Text("hello".into())],
        final_text: "hello".into(),
        session_id: Some("abc".into()),
        usage: Default::default(),
        error: None,
        unknown_json_lines: vec!["{\"mystery\":true}".into()],
    };

    assert_eq!(transcript.final_text, "hello");
    assert_eq!(transcript.unknown_json_lines.len(), 1);
}
```

```rust
#[test]
fn client_run_exposes_parsed_output_for_formatted_modes() {
    let client = Client::with_runner(Runner::with_executor(Box::new(|spec| CompletedRun {
        argv: spec.argv,
        exit_code: 0,
        stdout: "{\"response\":\"hello\"}\n".into(),
        stderr: String::new(),
    })));
    let request = Request::new("hello")
        .runner(RunnerKind::OpenCode)
        .output_mode(OutputMode::Formatted);

    let run = client.run(&request).expect("run should succeed");

    assert_eq!(run.final_text(), "hello");
    assert!(run.parsed_output().is_some());
}
```

Run: `cd rust && cargo test json_output_tests library_api_tests -- --nocapture`

Expected: compile failures for `Transcript`, `Event`, or `Run::parsed_output`.

- [ ] **Step 2: Add typed output model enums and structs**

```rust
// rust/src/output/model.rs
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    Text(String),
    Thinking(String),
    ToolCall(ToolCall),
    ToolResult(ToolResult),
    Error(String),
    RawUnknownJson(String),
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Usage {
    pub counts: BTreeMap<String, i64>,
    pub cost_usd: f64,
    pub duration_ms: i64,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Transcript {
    pub events: Vec<Event>,
    pub final_text: String,
    pub session_id: Option<String>,
    pub usage: Usage,
    pub error: Option<String>,
    pub unknown_json_lines: Vec<String>,
}
```

- [ ] **Step 3: Adapt existing JSON parsing code to produce `Transcript`**

```rust
// rust/src/output/parse.rs
pub fn parse_transcript(raw: &str, schema: &str) -> Transcript {
    let parsed = crate::json_output::parse_json_output(raw, schema);
    Transcript {
        events: parsed.events.into_iter().map(convert_event).collect(),
        final_text: parsed.final_text,
        session_id: (!parsed.session_id.is_empty()).then_some(parsed.session_id),
        usage: Usage {
            counts: parsed.usage,
            cost_usd: parsed.cost_usd,
            duration_ms: parsed.duration_ms,
        },
        error: (!parsed.error.is_empty()).then_some(parsed.error),
        unknown_json_lines: parsed.unknown_json_lines,
    }
}
```

This can begin as an adapter layer. Do not rewrite every schema parser in the first step if a conversion layer keeps scope down.

- [ ] **Step 4: Add `Run` and public `Error` types**

```rust
pub enum Error {
    InvalidRequest(String),
    Config(String),
    Spawn(std::io::Error),
    ToolFailed { exit_code: i32, stderr: String },
    OutputParse(String),
}

pub struct Run {
    plan: Plan,
    exit_code: i32,
    stdout: String,
    stderr: String,
    parsed_output: Option<Transcript>,
}
```

Update `Client::run` so formatted and JSON-oriented modes populate `parsed_output`.

- [ ] **Step 5: Re-run the focused tests**

Run: `cd rust && cargo test json_output_tests library_api_tests -- --nocapture`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/src/output/mod.rs rust/src/output/model.rs rust/src/output/parse.rs rust/src/output/render.rs rust/src/json_output.rs rust/src/invoke/plan.rs rust/src/lib.rs rust/tests/json_output_tests.rs rust/tests/library_api_tests.rs
git commit -m "Add typed Rust transcript and run models"
```

### Task 3: Add the Compatibility Sugar Parser

**Files:**
- Create: `rust/src/sugar.rs`
- Modify: `rust/src/parser.rs`
- Modify: `rust/src/invoke/request.rs`
- Modify: `rust/src/lib.rs`
- Modify: `rust/tests/parser_tests.rs`
- Modify: `rust/tests/library_api_tests.rs`

- [ ] **Step 1: Write the failing sugar-parser tests**

```rust
use call_coding_clis::{sugar, OutputMode, RunnerKind};

#[test]
fn sugar_parse_tokens_maps_common_cli_syntax() {
    let parsed = sugar::parse_tokens(["cc", ".fmt", "+3", "review this patch"])
        .expect("parse should succeed");

    assert_eq!(parsed.request.runner(), Some(RunnerKind::Claude));
    assert_eq!(parsed.request.output_mode(), Some(OutputMode::Formatted));
    assert_eq!(parsed.request.prompt(), "review this patch");
}

#[test]
fn sugar_parse_tokens_supports_provider_model_sugar() {
    let parsed = sugar::parse_tokens(["c", ":openai:gpt-5.4-mini", "debug this"])
        .expect("parse should succeed");

    assert_eq!(parsed.request.runner(), Some(RunnerKind::Codex));
    assert_eq!(parsed.request.provider(), Some("openai"));
    assert_eq!(parsed.request.model(), Some("gpt-5.4-mini"));
}
```

Run: `cd rust && cargo test parser_tests library_api_tests -- --nocapture`

Expected: compile failure for `sugar::parse_tokens` or assertion failures because the typed mapping does not exist yet.

- [ ] **Step 2: Implement `ParsedRequest` and the new sugar module**

```rust
pub struct ParsedRequest {
    pub request: Request,
    pub warnings: Vec<String>,
}

pub mod sugar {
    pub fn parse_tokens<I, S>(tokens: I) -> Result<ParsedRequest, Error>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let argv: Vec<String> = tokens.into_iter().map(Into::into).collect();
        let parsed = crate::parser::parse_args(&argv);
        let config = crate::config::load_config(None);
        let request = Request::from_parsed_args(&parsed, &config)?;
        Ok(ParsedRequest { request, warnings: Vec::new() })
    }
}
```

This step is allowed to reuse the existing parser. The success condition is that downstream callers can obtain a typed `Request` without calling `parse_args` or understanding CLI assembly internals.

- [ ] **Step 3: Make sugar parsing preserve warnings from fallback or compatibility paths**

```rust
let output_plan = crate::parser::resolve_output_plan(&parsed, Some(&config), &runner_name);
let warnings = output_plan.warnings.clone();
```

Plumb those warnings into `ParsedRequest` so downstream callers can surface the same guidance the CLI would have seen.

- [ ] **Step 4: Re-run the focused tests**

Run: `cd rust && cargo test parser_tests library_api_tests -- --nocapture`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/src/sugar.rs rust/src/parser.rs rust/src/invoke/request.rs rust/src/lib.rs rust/tests/parser_tests.rs rust/tests/library_api_tests.rs
git commit -m "Add Rust sugar parser compatibility layer"
```

### Task 4: Migrate the CLI to the New Library Path

**Files:**
- Modify: `rust/src/bin/ccc.rs`
- Modify: `rust/src/lib.rs`
- Modify: `rust/tests/help_tests.rs`
- Modify: `rust/tests/run_artifacts_tests.rs`
- Modify: `tests/test_ccc_contract_impl.py`

- [ ] **Step 1: Write one focused migration-regression test**

```rust
#[test]
fn ccc_binary_still_treats_help_as_top_level_help() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_ccc"))
        .arg("help")
        .output()
        .expect("ccc should run");

    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Usage:"));
}
```

In Python contract tests, keep one smoke for a real CLI shape that exercises runner selection plus formatting, for example:

```python
def test_rust_impl_codex_selector_still_resolves_in_contract(self):
    result = self.invoke("Rust", "c", ".fmt", "hello")
    self.assertEqual(result.returncode, 0)
```

Run: `cd rust && cargo test help_tests run_artifacts_tests -- --nocapture`

Expected: PASS before refactor, providing a safety rail for the migration.

- [ ] **Step 2: Switch the CLI main path to `sugar` plus `Client`**

```rust
let parsed_request = call_coding_clis::sugar::parse_tokens(args.clone())?;
let client = Client::new().with_config(load_config(None));
let plan = client.plan(&parsed_request.request)?;
let run = if plan.output_mode().is_streaming() {
    client.stream(&parsed_request.request, |event| render_cli_event(event))
} else {
    client.run(&parsed_request.request)
}?; 
```

Keep these flows CLI-only:

- `help`
- `version`
- `config`
- `config --edit`
- `add`
- terminal sanitization and final footer ordering
- session cleanup warnings and post-run cleanup

The CLI should consume the new library API without losing its current user-visible behavior.

- [ ] **Step 3: Re-run Rust and contract verification**

Run: `cd rust && cargo test`

Run: `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v`

Run: `./test_impl.sh rust`

Run: `just install-rs`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add rust/src/bin/ccc.rs rust/src/lib.rs rust/tests/help_tests.rs rust/tests/run_artifacts_tests.rs tests/test_ccc_contract_impl.py
git commit -m "Migrate Rust CLI onto typed library API"
```

### Task 5: docs.rs, README, and Changelog Polish

**Files:**
- Modify: `rust/Cargo.toml`
- Modify: `rust/README.md`
- Modify: `rust/src/lib.rs`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write the failing docs-focused checks**

Add or update doc tests at the crate root so the main examples compile:

```rust
//! ```rust
//! use call_coding_clis::{Client, Request, RunnerKind};
//!
//! let client = Client::new();
//! let request = Request::new("review this patch").runner(RunnerKind::Codex);
//! let _ = client.plan(&request);
//! ```
```

Run: `cd rust && cargo test --doc`

Expected: FAIL until the crate docs match the new API.

- [ ] **Step 2: Update docs.rs-oriented metadata and crate docs**

Add docs.rs metadata:

```toml
[package.metadata.docs.rs]
all-features = false
no-default-features = false
```

Update crate docs in `rust/src/lib.rs` so the first screen on docs.rs includes:

- one short overview paragraph
- one minimal example
- one richer example using `Client`, `Request`, and `sugar`
- links to the primary entry points
- a note that the typed API is primary and `sugar` is compatibility support

- [ ] **Step 3: Update the Rust README and add `CHANGELOG.md` if missing**

Backfill the changelog using the already researched release summary:

```md
# Changelog

## [0.1.2] - 2026-04-17
- Fix Windows release build issues for the published Rust package.

## [0.1.1] - 2026-04-17
- Initial public release of `ccc` with shared CLI controls, runner support, config flows, structured output, and release automation.
```

Update `rust/README.md` so library examples use the typed API first and mention the sugar parser as an optional compatibility layer.

- [ ] **Step 4: Re-run final documentation and release-surface verification**

Run: `cd rust && cargo test --doc`

Run: `cd rust && cargo test`

Run: `cargo check --manifest-path rust/Cargo.toml`

Run: `./test_impl.sh rust`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/Cargo.toml rust/README.md rust/src/lib.rs CHANGELOG.md
git commit -m "Document new Rust API and add changelog"
```

### Task 6: Final Review and Cleanup Pass

**Files:**
- Modify: any files touched above if review finds issues

- [ ] **Step 1: Run the full intended verification set**

Run: `cd rust && cargo test`

Run: `cd rust && cargo test --doc`

Run: `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v`

Run: `./test_impl.sh rust`

Run: `just install-rs`

Run: `git diff --check`

Expected: all commands pass with no whitespace or formatting issues.

- [ ] **Step 2: Review the public docs and the installed CLI directly**

Run: `ccc --help`

Run: `ccc help`

Run one direct smoke through the installed Rust CLI with the mock OpenCode runner:

```bash
env MOCK_JSON_SCHEMA=opencode \
  CCC_REAL_OPENCODE=tests/mock-coding-cli/mock_coding_cli.sh \
  ccc oc ..fmt "tool call"
```

Confirm:

- the CLI still works end-to-end
- formatted output still renders
- the installed binary matches the tested code
- the library docs and README agree on the new entry points

- [ ] **Step 3: Commit any final review fixes**

```bash
git add -A
git commit -m "Polish Rust API rollout"
```

# Rust API Design

## Goal

Create an idiomatic Rust library API for `ccc` that other crates can use directly without depending on CLI token parsing, raw argv assembly, or terminal-oriented rendering details.

The new API should still let downstream users opt into `ccc`-style sugar parsing when that is useful, but the primary surface must be typed and domain-oriented.

## Scope

This design covers the Rust crate in `rust/` only.

It does not require immediate rollout to other language implementations.

It also does not require an immediate crate split. The work should land inside the existing `ccc` package and `call_coding_clis` library target unless a later follow-up shows that a split is materially better.

## Non-Goals

- Renaming the published crate in this change
- Rewriting the entire CLI around a new architecture in one pass
- Removing all existing public exports immediately
- Broad multi-language parity work
- Full async API design in the first pass

## Problem

The current Rust library surface mostly exposes internal CLI support code:

- token-oriented argument parsing
- mutable runner registry details
- tuple-shaped command resolution
- stringly typed structured-output events
- CLI help printers
- config-edit and alias-write helpers that are mainly relevant to the binary

This makes the crate awkward for downstream Rust code. Callers that want to invoke coding CLIs through `ccc` currently have to think in terms of argv pieces and CLI parsing internals rather than stable Rust types.

## Design Summary

Add a new primary typed API layer and treat the current lower-level parser/config/rendering surface as implementation detail or compatibility surface.

The new library layering will be:

1. Primary typed API:
   - `Client`
   - `Request`
   - `Plan`
   - `Run`
   - `Event`
2. Compatibility sugar API:
   - `sugar::parse_*` helpers that desugar `ccc`-style tokens into typed requests
3. CLI-only layer:
   - top-level command dispatch
   - help/version/config-edit commands
   - terminal formatting policy
   - artifact footer emission
   - session-cleanup UX policy

## Recommended Crate Layout

Target module layout:

- `src/lib.rs`
- `src/exec.rs`
- `src/invoke/mod.rs`
- `src/invoke/request.rs`
- `src/invoke/plan.rs`
- `src/output/mod.rs`
- `src/output/model.rs`
- `src/output/parse.rs`
- `src/output/render.rs`
- `src/sugar.rs`
- `src/config/model.rs`
- `src/config/files.rs`
- `src/artifacts.rs`
- `src/bin/ccc.rs`

This is a target shape, not a required one-shot refactor. The initial implementation can move toward this layout incrementally.

## Primary Public API

### Client

`Client` owns reusable runtime/process configuration:

- binary overrides
- working directory
- environment overrides
- optionally loaded config
- execution backend

Representative shape:

```rust
pub struct Client {
    // private fields
}

impl Client {
    pub fn new() -> Self;
    pub fn with_cwd(mut self, cwd: impl Into<PathBuf>) -> Self;
    pub fn with_env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self;
    pub fn with_config(mut self, config: Config) -> Self;
    pub fn with_binary_override(mut self, runner: RunnerKind, path: impl Into<PathBuf>) -> Self;

    pub fn plan(&self, request: &Request) -> Result<Plan, Error>;
    pub fn run(&self, request: &Request) -> Result<Run, Error>;
    pub fn stream<F>(&self, request: &Request, on_event: F) -> Result<Run, Error>
    where
        F: FnMut(Event);
}
```

`Client` should be the normal entry point for downstream crates.

### Request

`Request` is a typed semantic description of one coding-agent call.

Representative fields:

- prompt
- runner
- provider
- model
- agent
- thinking level
- whether visible thinking is enabled
- output mode
- permission mode
- session policy

Representative shape:

```rust
pub struct Request {
    // private fields
}

impl Request {
    pub fn new(prompt: impl Into<String>) -> Self;
    pub fn runner(self, runner: RunnerKind) -> Self;
    pub fn provider(self, provider: impl Into<String>) -> Self;
    pub fn model(self, model: impl Into<String>) -> Self;
    pub fn agent(self, agent: impl Into<String>) -> Self;
    pub fn thinking(self, level: ThinkingLevel) -> Self;
    pub fn show_thinking(self, enabled: bool) -> Self;
    pub fn output_mode(self, mode: OutputMode) -> Self;
    pub fn permission_mode(self, mode: PermissionMode) -> Self;
    pub fn session_policy(self, policy: SessionPolicy) -> Self;
}
```

The public API should prefer enums and dedicated types over strings or bool soup where practical.

### Plan

`Plan` is the resolved invocation result before execution.

It should include:

- resolved runner identity
- resolved output strategy
- resolved `CommandSpec`
- warnings
- any parse/resolution notes relevant to the caller

Representative shape:

```rust
pub struct Plan {
    // private fields
}

impl Plan {
    pub fn command_spec(&self) -> &CommandSpec;
    pub fn runner(&self) -> RunnerKind;
    pub fn output_mode(&self) -> OutputMode;
    pub fn warnings(&self) -> &[Warning];
}
```

`plan()` is first-class because library consumers often want to inspect or log the final invocation before running it.

### Run

`Run` represents a completed invocation with higher-level accessors.

It should carry:

- the executed `Plan`
- exit status
- raw stdout/stderr
- parsed transcript/output when available

Representative shape:

```rust
pub struct Run {
    // private fields
}

impl Run {
    pub fn plan(&self) -> &Plan;
    pub fn exit_code(&self) -> i32;
    pub fn stdout(&self) -> &str;
    pub fn stderr(&self) -> &str;
    pub fn parsed_output(&self) -> Option<&Transcript>;
    pub fn final_text(&self) -> &str;
}
```

### Event

Streaming should use typed events rather than `(channel, chunk)` strings.

Representative shape:

```rust
pub enum Event {
    Text(String),
    Thinking(String),
    ToolCall(ToolCall),
    ToolResult(ToolResult),
    Error(String),
    RawStdout(String),
    RawStderr(String),
    RawUnknownJson(String),
}
```

The exact enum can be refined during implementation, but it must avoid the current stringly `event_type` model.

## Compatibility Sugar API

The library should also expose a desugaring parser so embedded users can reuse `ccc` syntax instead of rebuilding it.

This parser is a compatibility layer, not the primary API.

Target surface:

```rust
pub mod sugar {
    pub fn parse_str(input: &str) -> Result<ParsedRequest, Error>;
    pub fn parse_tokens<I, S>(tokens: I) -> Result<ParsedRequest, Error>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>;
}
```

`ParsedRequest` should be richer than the current `ParsedArgs`:

```rust
pub struct ParsedRequest {
    pub request: Request,
    pub warnings: Vec<Warning>,
}
```

Supported desugaring should include:

- runner selectors such as `cc`, `c`, `oc`, `g`
- alias references such as `@reviewer`
- thinking sugar such as `+3`
- provider/model sugar such as `:openai:gpt-5.4-mini`
- output mode sugar such as `.fmt` and `..json`
- `--` prompt boundary behavior

The key rule is that sugar parsing must terminate in the same typed `Request` path used by the primary API and the CLI.

## Execution Layer

The current `CommandSpec`, `CompletedRun`, and `Runner` primitives are still useful, but they should become the lower-level execution substrate.

Planned direction:

- keep `CommandSpec` as the explicit process-description type
- keep a reusable execution type, likely folded into or used by `Client`
- avoid making raw subprocess plumbing the main advertised API

The library should still expose an explicit escape hatch for callers who want the raw command:

- `Plan::command_spec()`
- possibly `Client::run_command(spec)` if needed later

## Output Model

Structured output handling should be split into:

1. parsing structured runner output into stable typed events/transcripts
2. optional human rendering for CLI usage

The typed layer should expose a transcript model roughly like:

```rust
pub struct Transcript {
    pub events: Vec<Event>,
    pub final_text: String,
    pub session_id: Option<String>,
    pub usage: Usage,
    pub error: Option<String>,
    pub unknown_json_lines: Vec<String>,
}
```

`output::render` should become optional presentation logic instead of being fused into parsing.

## Config Layer

The library should support explicit config injection and explicit config loading, but avoid forcing hidden env/file reads inside normal request execution.

Recommended split:

- pure config model and merge logic in the library layer
- file discovery/loading as explicit helper APIs
- config editing and alias-writing UX remain CLI-oriented

That means downstream crates can choose:

- no config
- explicitly loaded config
- their own config layering outside `ccc`

## Error Model

Add a crate-specific public error type.

The public error must be inspectable and semver-friendly.

Representative shape:

```rust
pub enum Error {
    InvalidRequest(String),
    Config(ConfigError),
    Spawn(std::io::Error),
    ToolFailed { exit_code: i32, stderr: String },
    OutputParse(String),
}
```

Implementation may use an opaque wrapper if needed for semver flexibility, but the public surface must be more structured than `String` or `anyhow::Error`.

## Migration Strategy

This should land incrementally.

### Phase 1

- Add the new typed API alongside the current exports
- Route new code paths through existing internals where practical
- Add documentation and examples for downstream crate use

### Phase 2

- Move the CLI to consume the typed API and sugar parser
- Narrow the set of default public re-exports in `lib.rs`
- Move clearly CLI-only helpers out of the public library surface

### Phase 3

- Decide whether to deprecate legacy public helpers
- Decide whether optional feature gates are justified for render/config extras

## Testing Strategy

Testing should cover:

- typed request to plan resolution
- sugar parsing to typed request equivalence
- plan to raw command assembly
- structured output parsing into typed events
- streaming event behavior
- CLI parity for the subset of behavior intentionally shared through sugar parsing

Cross-implementation tests remain the source of truth for shared CLI semantics.

Rust-only tests should be added for the new library API because this API is intentionally more Rust-specific than the shared CLI contract.

## Documentation Plan

Update these once implementation starts:

- `rust/README.md`
- crate-level Rust examples
- docs for the sugar parser
- docs for migration from low-level subprocess primitives to the typed API

If the repo still lacks `CHANGELOG.md` at implementation time, add one and backfill release notes for `0.1.1` and `0.1.2` using the already compiled release summary.

## Open Decisions

These do not block the initial implementation plan, but they should be resolved during execution:

1. Whether `Client` uses consuming or non-consuming builder methods
2. Whether `Run::final_text()` returns `&str` or `Option<&str>`
3. Whether raw stdout/stderr streaming should always be surfaced as events in formatted modes
4. Whether `output::render` should stay public in the first version of the typed API
5. Whether the long-term crate name and library target name should be unified in a later release

## Recommendation

Implement the new typed API inside the existing crate, keep the sugar parser as an explicit compatibility layer, and migrate the CLI onto that shared library path incrementally.

That approach gives downstream crates a real Rust API now without paying the cost of an early crate split or a one-shot rewrite.

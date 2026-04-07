# call-coding-clis Implementation Reference

## Shared Contract

Every language implementation must provide:

### Library API
- `CommandSpec` / `CodingCliCommandSpec` — holds argv, optional stdin_text, cwd, env overrides
- `CompletedRun` — holds argv, exit_code (int), stdout (str), stderr (str)
- `Runner` — has `run(spec) -> CompletedRun` and `stream(spec, callback) -> CompletedRun`
- `build_prompt_spec(prompt) -> CommandSpec` — trims prompt, rejects empty/whitespace-only, returns spec with argv=["opencode","run","<trimmed>"]
- Error format: `"failed to start <argv[0]>: <error>"` (just argv[0], not full argv)

### `ccc` CLI Binary
- `ccc "<Prompt>"` — exactly one positional arg
- Empty/whitespace prompt → stderr message, exit 1
- Missing/extra args → `usage: ccc "<Prompt>"` on stderr, exit 1
- On success: forward stdout/stderr from opencode, forward exit code via `std::process::exit()` or equivalent
- Prompt is trimmed before use

### Testing
- `CCC_REAL_OPENCODE` env var overrides the opencode binary for testing
- Cross-language contract tests live in `tests/test_ccc_contract.py` (Python unittest)
- Startup-failure tests: running with nonexistent binary should produce stderr containing "failed to start"

## Existing Implementations (for reference)

- Python: `python/call_coding_clis/runner.py`, `python/call_coding_clis/cli.py`
- Rust: `rust/src/lib.rs`, `rust/src/bin/ccc.rs`
- TypeScript: `typescript/src/index.js`, `typescript/src/ccc.js`
- C: `c/src/runner.c`, `c/src/runner.h`, `c/src/prompt_spec.c`, `c/src/ccc.c`
- Go: `go/ccc.go`, `go/cmd/ccc/main.go`
- Ruby: `ruby/lib/call_coding_clis/runner.rb`, `ruby/bin/ccc`
- Perl: `perl/lib/Call/Coding/Clis/Runner.pm`, `perl/bin/ccc`
- C++: `cpp/src/runner.cpp`, `cpp/src/ccc_cli.cpp`, `cpp/include/ccc/`

## Feature Parity Matrix

| Feature | Python | Rust | TypeScript | C | Go | Ruby | Perl | C++ |
|---------|--------|------|------------|---|-----|------|------|-----|
| build_prompt_spec | yes | yes | yes | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes | yes | yes | yes |
| Runner.stream | yes | yes (real concurrent) | yes | no | yes (real concurrent) | yes | yes (fake passthrough) | yes (fake passthrough) |
| ccc CLI | yes | yes | yes | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes | yes | yes | yes |
| Stdin/CWD/Env support | yes | yes | yes | yes | yes | yes | yes | yes |
| Startup failure reporting | yes | yes | yes | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes | yes | yes | yes |
| CCC_REAL_OPENCODE | yes | yes | yes | yes | yes | yes | yes | yes |

## Licensing

Unlicense — see `UNLICENSE` at repo root.

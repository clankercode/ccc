# Shared Changes

This file records shared `ccc` features, fixes, and semantic changes.

Use it when:
- a change affects the shared CLI contract
- a change affects parser/config/help semantics expected across implementations
- a change affects runner execution behavior, stdin/env behavior, or shared test expectations

Entry format:

```md
## YYYY-MM-DD

- Change: short description of the semantic change
- Required implementations: Python and Rust
- Additional rollout: deferred | rolled out to <languages>
- Shared tests updated: <tests>
- Notes: optional short context
```

## 2026-04-09

- Change: Codex runner now uses `codex exec` for non-interactive execution instead of bare `codex`
- Required implementations: Python and Rust
- Additional rollout: rolled out to C, C++, Go, TypeScript, Perl, PHP, Ruby, Crystal, D, Elixir, F#, Haskell, Nim, OCaml parser/tests, PureScript, Zig
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_harness.py`
- Notes: ASM remains on the first-pass prompt-only contract path

- Change: `--show-thinking` / `--no-show-thinking` added to Python and Rust with config-backed `show_thinking` defaulting off
- Required implementations: Python and Rust
- Additional rollout: deferred
- Shared tests updated: `tests/test_ccc_contract_impl.py`, `tests/test_parser_config.py`, `tests/test_runner.py`, `rust/tests/parser_tests.rs`, `rust/tests/config_tests.rs`, `rust/tests/help_tests.rs`
- Notes: visible-thinking support is runner-specific and not yet rolled out to the other language implementations

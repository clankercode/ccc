# Microplan

## Current Milestone
Improve cross-language runner startup-failure robustness and keep repo state accurate.

## Iteration 10
- Goal: make startup-failure coverage explicit for the Rust runner as well.
- Approach: add regression tests for missing-binary failures in both `run` and `stream`, then keep the broader milestone docs in sync with the now-covered languages.
- Files to change: `tests/rust_runner.rs`, `MICROPLAN.md`, and goal-loop state.
- Verification: `PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_ccc_contract`, `node --test typescript/tests/runner.test.mjs`, `cargo test`, and `make test` in `c/`.
- Adjacent fixes: avoid changing current runtime behavior when only coverage is missing.

## Planned Next Iterations
- Iteration 11: decide whether to deepen C `ccc` parity or extend startup-failure coverage to additional stream/runtime edge cases in Python and TypeScript.
- Iteration 12+: implement expanded `ccc` syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- current shared `ccc` behavior doc added at `CCC_BEHAVIOR_CONTRACT.md`
- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- C runner startup failures now report a non-empty stderr message before exiting with failure
- Python and TypeScript runners now return completed startup-failure results for missing binaries instead of throwing
- Rust runner now has explicit regression coverage for startup failures in both `run` and `stream`

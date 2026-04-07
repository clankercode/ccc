# Microplan

## Current Milestone
Improve cross-language runner startup-failure robustness and keep repo state accurate.

## Iteration 11
- Goal: extend startup-failure parity into Python and TypeScript stream behavior.
- Approach: add failing stream tests first, then make the smallest changes needed so stream mode preserves startup-failure stderr in both emitted events and returned results.
- Files to change: Python and TypeScript runner files, tests, `README.md`, `MICROPLAN.md`, and goal-loop state.
- Verification: `PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_ccc_contract`, `node --test typescript/tests/runner.test.mjs`, `cargo test`, and `make test` in `c/`.
- Adjacent fixes: keep the shared `ccc` contract unchanged while tightening non-CLI runner parity.

## Planned Next Iterations
- Iteration 12: decide whether to deepen C `ccc` parity or keep closing cross-language runner event-shape gaps.
- Iteration 13+: implement expanded `ccc` syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- current shared `ccc` behavior doc added at `CCC_BEHAVIOR_CONTRACT.md`
- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- C runner startup failures now report a non-empty stderr message before exiting with failure
- Python and TypeScript runners now return completed startup-failure results for missing binaries instead of throwing
- Rust runner now has explicit regression coverage for startup failures in both `run` and `stream`
- Python and TypeScript stream mode now preserve startup-failure stderr in returned results, and TypeScript also emits it as a `stderr` event

# Microplan

## Current Milestone
Improve cross-language runner startup-failure robustness and keep repo state accurate.

## Iteration 9
- Goal: normalize missing-binary startup failures in the implemented Python and TypeScript runners.
- Approach: add failing runner tests first, make the smallest runtime changes that return a completed failure result instead of raising, and refresh stale docs/goal state.
- Files to change: Python and TypeScript runner files, tests, `README.md`, `MICROPLAN.md`, and goal-loop state.
- Verification: `PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_ccc_contract`, `node --test typescript/tests/runner.test.mjs`, `cargo test`, and `make test` in `c/`.
- Adjacent fixes: keep the shared `ccc` contract unchanged while closing the cross-language startup-failure gap.

## Planned Next Iterations
- Iteration 10: decide whether to deepen C `ccc` parity or add more shared runner-failure coverage across every implemented language.
- Iteration 11+: implement expanded `ccc` syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- current shared `ccc` behavior doc added at `CCC_BEHAVIOR_CONTRACT.md`
- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`
- C runner startup failures now report a non-empty stderr message before exiting with failure
- Python and TypeScript runners now return completed startup-failure results for missing binaries instead of throwing

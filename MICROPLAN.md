# Microplan

## Current Milestone
Define and implement the first shared `ccc` CLI shape.

## Iteration 3
- Goal: add matching Python and Rust `ccc` entrypoints.
- Approach: keep the first contract tiny, with `ccc "<Prompt>"` turning into a command spec that later providers can execute.
- Files to change: Python package files, Rust crate files, tests, packaging/entrypoint files, `README.md`, and goal-loop state.
- Verification: Python tests and `cargo test` both pass.
- Adjacent fixes: keep the CLI contract easy to port to TS, Elixir, OCaml, and C later.

## Planned Next Iterations
- Iteration 4: document the `ccc` CLI contract and add remaining call-coding-clis roadmap artifacts.
- Iteration 5+: scaffold the next language deliverables needed after `precurl` integration stabilizes.

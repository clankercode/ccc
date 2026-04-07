# Microplan

## Current Milestone
Build `call-coding-clis` in the agreed order: Python first, then Rust.

## Iteration 1
- Goal: establish repo state and Python package skeleton.
- Approach: add license, basic package layout, subprocess abstraction, tests, and updated README.
- Approach: add license, basic package layout, subprocess abstraction, tests, updated README, and leave room for a shared `ccc` CLI contract.
- Files to change: `README.md`, `UNLICENSE`, Python package files, tests, packaging files, `.gitignore` if needed.
- Verification: Python test suite passes.
- Adjacent fixes: keep the API small so the Rust crate can mirror it later.
- Adjacent fixes: keep the API small so the Rust crate and future `ccc` CLIs can mirror it later.

## Planned Next Iterations
- Iteration 2: Rust crate with mirrored minimal API and tests.
  - Goal: add a small `call-coding-clis` Rust crate suitable for `precurl` integration.
  - Approach: create `Cargo.toml`, implement a subprocess-oriented runner with injectable execution hooks, and keep the API close to the Python package.
  - Files to change: Rust crate files, `README.md`, and goal-loop state.
  - Verification: `cargo test` passes.
  - Adjacent fixes: keep naming and result shapes aligned with the future `ccc` CLI contract.
- Iteration 3: define and implement the first shared `ccc` CLI shape, with `ccc "<Prompt>"` working.
- Iteration 4+: docs and remaining language roadmap artifacts.

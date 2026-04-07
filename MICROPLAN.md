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
- Iteration 3: define and implement the first shared `ccc` CLI shape, with `ccc "<Prompt>"` working.
- Iteration 4+: docs and remaining language roadmap artifacts.

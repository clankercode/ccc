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
- Iteration 4: document the gap between the shipped `ccc "<Prompt>"` contract and the planned expanded syntax, without changing implementation yet.
- Iteration 5: write the parser/config microplan for `@alias`, `+0..+4`, `:provider:model` or `:model`, runner selectors, and config-backed defaults.
- Iteration 6+: implement expanded syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`

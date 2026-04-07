# Primary Goal
Define and implement the first shared `ccc` CLI shape in `call-coding-clis`, with matching Python and Rust entrypoints and `ccc "<Prompt>"` working.

## Acceptance Criteria
- A microplan exists in this repo and is kept current.
- The repo has an `UNLICENSE` file.
- Python exposes a `ccc` CLI entrypoint.
- Rust exposes a `ccc` CLI entrypoint.
- `ccc "<Prompt>"` works in both implementations with the same first-pass argument shape.
- The first-pass CLI contract is documented clearly enough to guide the later language ports.
- Tests cover the new CLI argument handling and command-shape behavior.
- Milestone commits are created at convenient intervals during development.

## Current Status
- Iteration: 4
- Newly satisfied AC: ["Milestone commits are created at convenient intervals during development."]
- Remaining AC: []

## Current Plan
- The shared `ccc` CLI shape and planned syntax notes are committed.
- Auto-advance into the next goal: write the parser/config microplan for expanded `ccc` syntax and then begin remaining language roadmap scaffolding.

## Blockers / Notes
- Keep the first `ccc` contract intentionally small.
- The only locked user-facing behavior is `ccc "<Prompt>"`.
- Preserve room for provider/model selection without overdesigning the initial CLI.
- Expanded syntax is now planned but not committed as current behavior: `@alias`, `+0..+4`, `:provider:model` or `:model`, and runner selectors.
- Do not treat config-backed aliases or default provider/model resolution as accepted behavior until the parser and config design are written down.

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for the remaining `call-coding-clis` deliverables (docs, C, TS, Elixir, OCaml, and any cleanup needed for `precurl` integration), update this file, and continue automatically.

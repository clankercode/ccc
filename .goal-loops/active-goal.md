# Primary Goal
Add the next concrete `call-coding-clis` implementation after Python and Rust: a TypeScript scaffold with the same minimal runner shape and a first-pass `ccc` entrypoint.

## Acceptance Criteria
- A microplan exists in this repo and is kept current.
- The repo has an `UNLICENSE` file.
- A TypeScript package scaffold exists.
- TypeScript exposes the same minimal runner concepts as Python and Rust.
- TypeScript exposes a first-pass `ccc` entrypoint with `ccc "<Prompt>"` behavior.
- TypeScript tests cover the new runner and CLI command-shape behavior.
- Repo docs are updated to reflect the new implementation state.
- Milestone commits are created at convenient intervals during development.

## Current Status
- Iteration: 5
- Newly satisfied AC: ["A TypeScript package scaffold exists.", "TypeScript exposes the same minimal runner concepts as Python and Rust.", "TypeScript exposes a first-pass `ccc` entrypoint with `ccc \"<Prompt>\"` behavior.", "TypeScript tests cover the new runner and CLI command-shape behavior.", "Repo docs are updated to reflect the new implementation state."]
- Remaining AC: ["Milestone commits are created at convenient intervals during development."]

## Current Plan
- Write the TypeScript microplan.
- Add tests first for a small runner abstraction and `ccc` prompt-spec behavior.
- Implement the TypeScript scaffold minimally.
- Commit milestone and reassess.

## Blockers / Notes
- Keep the first `ccc` contract intentionally small.
- The only locked user-facing behavior is `ccc "<Prompt>"`.
- Preserve room for provider/model selection without overdesigning the initial CLI.
- Expanded syntax is now planned but not committed as current behavior: `@alias`, `+0..+4`, `:provider:model` or `:model`, and runner selectors.
- Do not treat config-backed aliases or default provider/model resolution as accepted behavior until the parser and config design are written down.

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for the remaining `call-coding-clis` deliverables (docs, C, TS, Elixir, OCaml, and any cleanup needed for `precurl` integration), update this file, and continue automatically.

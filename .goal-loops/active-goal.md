# Primary Goal
Add the next concrete `call-coding-clis` implementation after TypeScript: a C scaffold with a minimal runner-facing shape and a first-pass `ccc` entrypoint.

## Acceptance Criteria
- A microplan exists in this repo and is kept current.
- The repo has an `UNLICENSE` file.
- A C scaffold exists.
- The C scaffold documents or exposes the same minimal runner-facing concepts as the other implementations.
- The C scaffold exposes a first-pass `ccc` entrypoint with `ccc "<Prompt>"` behavior.
- C tests or smoke checks cover the CLI command-shape behavior.
- Repo docs are updated to reflect the new implementation state.
- Milestone commits are created at convenient intervals during development.

## Current Status
- Iteration: 6
- Newly satisfied AC: ["A C scaffold exists.", "The C scaffold documents or exposes the same minimal runner-facing concepts as the other implementations.", "The C scaffold exposes a first-pass `ccc` entrypoint with `ccc \"<Prompt>\"` behavior.", "C tests or smoke checks cover the CLI command-shape behavior.", "Repo docs are updated to reflect the new implementation state."]
- Remaining AC: ["Milestone commits are created at convenient intervals during development."]

## Current Plan
- Write the C microplan.
- Add a small smoke-style test first for `ccc "<Prompt>"` behavior.
- Implement the C scaffold minimally.
- Commit milestone and reassess.

## Blockers / Notes
- Keep the first `ccc` contract intentionally small.
- The only locked user-facing behavior is `ccc "<Prompt>"`.
- Preserve room for provider/model selection without overdesigning the initial CLI.
- Expanded syntax is now planned but not committed as current behavior: `@alias`, `+0..+4`, `:provider:model` or `:model`, and runner selectors.
- Do not treat config-backed aliases or default provider/model resolution as accepted behavior until the parser and config design are written down.

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for the remaining `call-coding-clis` deliverables (docs, C, TS, Elixir, OCaml, and any cleanup needed for `precurl` integration), update this file, and continue automatically.

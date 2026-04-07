# Primary Goal
Improve `call-coding-clis` cross-language runner robustness by normalizing startup-failure behavior in the implemented Python and TypeScript runners.

## Acceptance Criteria
- A microplan exists in this repo and is kept current.
- The repo has an `UNLICENSE` file.
- Python runner returns a completed failure result when process startup fails.
- TypeScript runner returns a completed failure result when process startup fails.
- Existing shared `ccc` behavior stays unchanged.
- Repo docs are updated to reflect the current implementation state.
- Milestone commits are created at convenient intervals during development.

## Current Status
- Iteration: 9
- Newly satisfied AC: ["Python runner returns a completed failure result when process startup fails.", "TypeScript runner returns a completed failure result when process startup fails.", "Existing shared `ccc` behavior stays unchanged.", "Repo docs are updated to reflect the current implementation state.", "Milestone commits are created at convenient intervals during development."]
- Remaining AC: []

## Current Plan
- Python and TypeScript now normalize missing-binary startup failures to completed results with stderr text.
- Shared `ccc` contract checks remain green across Python, Rust, TypeScript, and C.
- After this checkpoint, the next likely `call-coding-clis` step is choosing between deeper C parity and broader cross-language runner-failure normalization.

## Blockers / Notes
- Keep the first `ccc` contract intentionally small.
- The only locked user-facing behavior is `ccc "<Prompt>"`.
- Preserve room for provider/model selection without overdesigning the initial CLI.
- Expanded syntax is now planned but not committed as current behavior: `@alias`, `+0..+4`, `:provider:model` or `:model`, and runner selectors.
- Do not treat config-backed aliases or default provider/model resolution as accepted behavior until the parser and config design are written down.
- Keep `CCC_BEHAVIOR_CONTRACT.md` as the source of truth for currently implemented cross-language `ccc` behavior.
- C `ccc` still intentionally stays at the smoke/command-shape layer even though the C runner library is more capable.

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for runner-parity gaps, TS/C follow-up work, Elixir/OCaml scaffolds, and any cleanup needed for `precurl` integration, update this file, and continue automatically.

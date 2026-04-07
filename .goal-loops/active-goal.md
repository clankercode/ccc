# Primary Goal
Polish remaining gaps in both `call-coding-clis` and `precurl` identified during the last review cycle.

## Acceptance Criteria
- C `ccc` trims prompts before passing to runner (all 4 languages now trim consistently)
- Python and TypeScript CLIs print clean single-line errors on empty/whitespace prompts (no tracebacks)
- `precurl` README no longer contains stale claims about "next" work that is already done
- `CCC_BEHAVIOR_CONTRACT.md` documents prompt trimming as part of the shared contract
- All test suites pass across all languages and both projects
- All changes are committed

## Current Status
- Iteration: 1
- Newly satisfied AC: ["C `ccc` trims prompts before passing to runner", "Python and TypeScript CLIs print clean single-line errors", "precurl README updated", "CCC_BEHAVIOR_CONTRACT.md updated", "All test suites pass", "All changes committed"]
- Remaining AC: []

## Current Plan
- All gaps from the last review are resolved.
- Both repos are clean, all tests pass.

## Blockers / Notes
- Elixir and OCaml remain design-only scaffolds (by design)
- C `ccc_build_prompt_command` in `prompt_spec.c` intentionally does NOT trim — trimming happens in the CLI layer, matching the split in other languages
- `precurl` next steps could include: additional unsafe signal patterns, TUI polish, prompt-injection hardening
- `call-coding-clis` next steps could include: expanded `ccc` syntax (`@alias`, `+N`, `:model`), config file support, runner selection

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for runner-parity gaps, TS/C follow-up work, Elixir/OCaml scaffolds, and any cleanup needed for `precurl` integration, update this file, and continue automatically.

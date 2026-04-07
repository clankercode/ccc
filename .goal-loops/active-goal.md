# Primary Goal
Build the first usable `call-coding-clis` milestone: a Python package first, then a Rust crate, that can reliably invoke coding CLIs with a small shared abstraction suitable for `precurl`.

## Acceptance Criteria
- A microplan exists in this repo and is kept current.
- The repo has an `UNLICENSE` file.
- A Python package named `call_coding_clis` exists with a small public API for running coding CLIs and capturing/streaming results.
- Python tests cover the core process-invocation behavior with mockable execution.
- A Rust crate exists with a comparable first-pass API for invoking coding CLIs.
- Rust tests cover core invocation/result handling.
- The repo docs capture the cross-language requirement that each library bundles a same-shape CLI named `ccc`, with `ccc "<Prompt>"` supported.
- The repo documentation explains current scope, supported runners, and the staged roadmap for Rust, docs, C, Python, TS, Elixir, and OCaml.
- Milestone commits are created at convenient intervals during development.

## Current Status
- Iteration: 2
- Newly satisfied AC: ["A Rust crate exists with a comparable first-pass API for invoking coding CLIs.", "Rust tests cover core invocation/result handling.", "The repo documentation explains current scope, supported runners, and the staged roadmap for Rust, docs, C, Python, TS, Elixir, and OCaml."]
- Remaining AC: ["Milestone commits are created at convenient intervals during development."]

## Current Plan
- Python and Rust milestones are implemented and verified.
- Create a milestone commit for the Rust checkpoint.
- Reassess the acceptance criteria.
- Auto-advance to the next `call-coding-clis` milestone by defining and implementing the first shared `ccc` CLI contract.

## Blockers / Notes
- `precurl` will consume the Rust library first, but Python goes first for this repo.
- Keep the abstraction minimal and subprocess-oriented.
- Preserve room for a shared `ccc` CLI contract across languages.

## ON_GOAL_COMPLETE_NEXT_STEPS
When this goal is satisfied, microplan the next tasks for the remaining `call-coding-clis` deliverables (docs, C, TS, Elixir, OCaml, and any cleanup needed for `precurl` integration), update this file, and continue automatically.

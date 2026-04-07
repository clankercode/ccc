# Microplan

## Current Milestone
Add the C scaffold as the next concrete `call-coding-clis` implementation.

## Iteration 7
- Goal: create a minimal C scaffold with a first-pass `ccc` entrypoint.
- Approach: keep the first version extremely small, implement the prompt-to-command-shape behavior, and use smoke-style tests/build checks.
- Files to change: C scaffold files, tests/build scripts, `README.md`, `MICROPLAN.md`, and goal-loop state.
- Verification: the C smoke checks pass locally.
- Adjacent fixes: keep the public contract aligned with the shared `ccc` behavior.

## Planned Next Iterations
- Iteration 8: reassess whether to deepen TypeScript/C or move to design-first Elixir/OCaml scaffolds.
- Iteration 9+: implement expanded `ccc` syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`

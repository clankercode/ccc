# Microplan

## Current Milestone
Add the TypeScript scaffold as the next concrete `call-coding-clis` implementation.

## Iteration 6
- Goal: create a minimal TypeScript package with runner abstractions and a first-pass `ccc` entrypoint.
- Approach: mirror the Python/Rust concepts closely, keep the package tiny, and test the prompt-to-command-spec behavior first.
- Files to change: TypeScript package files, tests, `README.md`, `MICROPLAN.md`, and goal-loop state.
- Verification: the TypeScript tests pass locally.
- Adjacent fixes: keep names and CLI behavior aligned with the shared contract.

## Planned Next Iterations
- Iteration 7: reassess whether to implement Elixir/OCaml/C scaffolds or deepen TypeScript functionality.
- Iteration 8+: implement expanded `ccc` syntax only after precedence, ambiguity handling, and config shape are explicitly documented.

## Current Output

- planned parser/config design doc added at `CCC_PARSER_CONFIG_DESIGN.md`
- remaining-language scaffold doc added at `ROADMAP_LANGUAGE_SCAFFOLDS.md`

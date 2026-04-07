# OCaml Scaffold

## Purpose

Design-first scaffold for a future OCaml implementation of `call-coding-clis`.

## Current Status

- design-only scaffold
- no implementation or packaging commitment yet

## Intended Package Shape

- library over subprocess execution
- bundled `ccc` executable later

## Minimal First-Pass Contract

- `ccc "<Prompt>"`
- maps to the shared prompt-spec behavior only

See also:

- `CCC_BEHAVIOR_CONTRACT.md`
- `CCC_PARSER_CONFIG_DESIGN.md`

## Candidate Implementation Directions

- `Unix`-based subprocess path
- streaming via pipes/channels
- concrete library choices deferred until implementation

## Proposed Public Surface

- prompt-spec builder
- completed-run result
- runner abstraction with `run`/`stream` intent

## Open Questions

- dune layout
- opam packaging timing
- async vs sync execution surface

## Non-Goals For This Scaffold

- expanded parser behavior
- config schema
- parity claims beyond the current `ccc "<Prompt>"` contract

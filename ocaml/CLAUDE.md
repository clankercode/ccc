# OCaml Agent Notes

- Keep OCaml changes isolated to this directory.
- Use `dune` sequentially. Do not run parallel `dune build`, `dune test`, or `dune runtest` jobs in this tree; concurrent dune processes can deadlock here.
- Prefer the repo's existing `make` targets or a single direct `dune` command at a time.
- Keep `ocaml/_build/` and `ocaml/_opam/` as local build artifacts; do not edit generated files by hand.
- When changing parser/config/help behavior, update the OCaml unit tests that cover the same contract.

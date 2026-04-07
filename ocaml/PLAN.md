# OCaml Implementation Plan: call-coding-clis

## 1. Dune Workspace Layout

```
ocaml/
├── dune-project          # (lang dune 3.16)
├── dune-workspace        # (default for OCaml ≥ 5.0)
├── Makefile              # convenience targets (build, test, verify)
├── bin/
│   ├── dune              # (executable ccc)
│   └── ccc.ml            # CLI entry point
├── lib/
│   ├── dune              # (library ccc_lib)
│   ├── command_spec.ml   # CommandSpec type + builder
│   ├── completed_run.ml  # CompletedRun type
│   ├── prompt_spec.ml    # build_prompt_spec (wraps verified logic)
│   ├── runner.ml         # Runner: run + stream
│   └── mli/              # separate .mli for every .ml
├── test/
│   ├── dune              # (tests)
│   ├── test_prompt_spec.ml
│   ├── test_runner.ml
│   └── test_cli.ml
└── verify/
    ├── dune              # (library ccc_verify, no install)
    ├── prompt_trim.ml    # pure extraction-friendly prompt logic
    ├── prompt_trim.mli
    └── prompt_trim.mlw   # Why3 model
```

### dune-project

```
(lang dune 3.16)

(using fmt 0.2)

(package
  (name call-coding-clis)
  (synopsis "OCaml implementation of call-coding-clis")
  (license Unlicense))

(generate_opam_files)
```

The `verify/` library is a separate dune library that depends only on pure
logic — no Unix, no I/O — making it suitable for Why3 extraction. The main
`lib/` library wraps the verified logic under the same API.

## 2. Build Instructions

### Prerequisites

```
opam init          # if not already initialized
opam switch create 5.2  # OCaml ≥ 5.0 for effect handlers, modern GADTs
eval $(opam env)
opam install dune alcotest
```

### Build & Test

```bash
make build          # dune build @install
make test           # dune runtest
make verify         # why3 prove (see section 10)
make clean          # dune clean
```

### Makefile

```makefile
.PHONY: build test verify clean

build:
	dune build @install

test:
	dune runtest

verify:
	why3 prove -P alt-ergo,cvc5 --dir verify prompt_trim

clean:
	dune clean
```

## 3. Library API — OCaml Modules and Types

### `Ccc_lib.Command_spec`

```ocaml
type t = {
  argv : string list;
  stdin_text : string option;
  cwd : string option;
  env : (string * string) list;
}

val make : string list -> t
val with_stdin : string -> t -> t
val with_cwd : string -> t -> t
val with_env : string -> string -> t -> t
```

### `Ccc_lib.Completed_run`

```ocaml
type t = {
  argv : string list;
  exit_code : int;
  stdout : string;
  stderr : string;
}
```

### `Ccc_lib.Prompt_spec`

```ocaml
val build_prompt_spec : string -> (Ccc_lib.Command_spec.t, [> `Empty_prompt]) result
```

Returns `Ok spec` with `spec.argv = ["opencode"; "run"; trimmed_prompt]`, or
`Error `Empty_prompt` if the trimmed input is empty. The verified variant lives
in section 10.

### `Ccc_lib.Runner`

```ocaml
type t

val make : unit -> t
val with_executor : (Ccc_lib.Command_spec.t -> Ccc_lib.Completed_run.t) -> t -> t
val with_stream_executor :
  (Ccc_lib.Command_spec.t -> (string -> string -> unit) -> Ccc_lib.Completed_run.t)
  -> t -> t
val run : t -> Ccc_lib.Command_spec.t -> Ccc_lib.Completed_run.t
val stream : t -> Ccc_lib.Command_spec.t -> (string -> string -> unit) -> Ccc_lib.Completed_run.t
```

### `Ccc_lib.Error_format`

```ocaml
val startup_failure : string -> string -> string
(** [startup_failure argv0 error] produces
    "failed to start {argv0}: {error}\n" *)
```

This matches the cross-language contract exactly (see IMPLEMENTATION_REFERENCE.md).
The function takes a single `string` for argv0, never a list, enforced at the
type level.

## 4. Subprocess via Unix Module

The default executor uses `Unix.create_process` to avoid external dependencies:

```ocaml
let pid = Unix.create_process argv0 (Array.of_list argv)
            Unix.stdin Unix.stdout Unix.stderr
```

### `run` path:
1. `Unix.pipe` for stdout and stderr capture
2. `Unix.create_process` with pipes as stdout/stderr
3. `Unix.read` loops drain both pipes (read both to avoid deadlocks)
4. `Unix.waitpid` extracts exit status
5. `Unix.close` all pipe fds
6. Catch `Sys_error` on `create_process` failure → `Error_format.startup_failure argv0 msg`

### `stream` path (v1, buffered):
Delegate to the `run` executor, then invoke callbacks on non-empty stdout/stderr.
Future work: `Unix.select`-driven event loop for true streaming.

### Environment merging:
`Unix.environment ()` returns the current env as `string array`.
Prepend overrides: later entries in the `Command_spec.env` alist shadow earlier
entries in the inherited env.

### `CCC_REAL_OPENCODE`:
Checked in the default executor. If set, replaces `spec.argv` with
`[env_value; spec.prompt_arg]`. This mirrors the Python and Rust behavior where
`CCC_REAL_OPENCODE` overrides the binary used for testing.

### Robustness notes:
- Close all pipe fds in both parent and child on every code path (use `try/finally`)
- `Unix.waitpid [] pid` avoids collecting unrelated child exit statuses
- Read both stdout and stderr before `waitpid` to prevent pipe-buffer deadlock
- Use `Unix.set_close_on_exec` on pipe fds to prevent fd leaks in the child

## 5. `ccc` CLI Binary

`bin/ccc.ml`:

```ocaml
let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | [prompt] ->
    (match Ccc_lib.Prompt_spec.build_prompt_spec prompt with
     | Ok spec ->
       let result = Ccc_lib.Runner.(make () |> run spec) in
       if result.stdout <> "" then output_string stdout result.stdout;
       if result.stderr <> "" then output_string stderr result.stderr;
       exit result.exit_code
     | Error `Empty_prompt ->
       prerr_endline "prompt must not be empty";
       exit 1)
  | _ ->
    prerr_endline "usage: ccc \"<Prompt>\"";
    exit 1
```

Exit code forwarding uses `Stdlib.exit` which bypasses at_exit handlers —
matching Rust's `std::process::exit` semantics and the cross-language contract.

Usage message matches the contract: `usage: ccc "<Prompt>"` on stderr.

## 6. Prompt Trimming

`String.trim` from the OCaml stdlib strips leading/trailing ASCII whitespace
(space, tab, newline, carriage return, etc.). **Note:** `String.trim` does NOT
handle Unicode whitespace in any OCaml version. This matches the Rust
(`str::trim`) and Python (`str.strip`) behavior for the ASCII subset, which
is what matters for CLI prompt arguments.

The contract:
- `String.trim` applied to any string `s` yields `t` where:
  - `t` has no leading or trailing whitespace
  - If `s` is all whitespace, `t = ""`
- Empty rejection: after trimming, if result is `""`, return `Error `Empty_prompt`

Formal proof of these properties lives in section 10.

## 7. Error Format — argv[0] Only

On subprocess startup failure (`Sys_error` caught during `Unix.create_process`):

```
"failed to start <argv[0]>: <error message>\n"
```

Only `List.hd spec.argv` (or `"(unknown)"` on empty argv) appears. The full
argv is never included. This is enforced at the type level by
`Error_format.startup_failure` taking a single `string` (the argv0), not a
`string list`. This matches the Python (`spec.argv[0]`) and Rust
(`spec.argv.first().unwrap_or("(unknown)")`) behavior.

## 8. Exit Code Forwarding

- Success path: child's raw exit status → `int` via `Unix.waitpid` status
  extraction, forwarded via `Stdlib.exit`
- Startup failure: exit code 1
- `Completed_run.exit_code` is always the concrete OS exit status (0–255 on
  POSIX). No normalization.

Matches Python (`process.returncode`), Rust (`ExitStatus::from_raw(1 << 8)` for
failure), and the cross-language contract.

## 9. Test Strategy

### Framework: Alcotest

```scheme
(tests
  (libraries alcotest ccc_lib))
```

### Unit tests (no subprocess):
- `test_prompt_spec.ml`: empty string, whitespace-only, whitespace-wrapped,
  normal prompt → verify `argv` shape and `Error` cases
- `test_error_format.ml`: verify format string contains argv0 and error, trailing newline

### Integration tests (require subprocess):
- `test_runner.ml`: `CCC_REAL_OPENCODE` override mechanism, nonexistent binary
  → stderr contains "failed to start", exit code 1
- `test_cli.ml`: arg count validation, empty prompt exit code 1, usage message

### `CCC_REAL_OPENCODE` handling:
Tests read the env var and pass it to a `Runner` configured with the overridden
binary. Tests needing a real binary use a trivial `true` or `echo` command.

```ocaml
let () =
  let open Alcotest in
  run "ccc_lib"
    [
      ("prompt_spec", [
        test_case "empty prompt rejected" `Quick (fun () ->
          let res = Ccc_lib.Prompt_spec.build_prompt_spec "" in
          check (result string string) "empty" (Error `Empty_prompt) res);
        test_case "whitespace trimmed" `Quick (fun () ->
          match Ccc_lib.Prompt_spec.build_prompt_spec "  hello  " with
          | Ok spec ->
            check (list string) "argv" ["opencode"; "run"; "hello"] spec.argv
          | Error _ -> fail "expected Ok");
      ]);
      ("error_format", [
        test_case "contains argv0" `Quick (fun () ->
          let msg = Ccc_lib.Error_format.startup_failure "mybin" "not found" in
          string_contains ~sub:"mybin" msg |> check bool "argv0" true);
        test_case "starts with prefix" `Quick (fun () ->
          let msg = Ccc_lib.Error_format.startup_failure "x" "e" in
          let prefix = "failed to start x: e\n" in
          check string "format" prefix msg);
      ]);
    ]
```

## 10. OCaml-Specific Design Decisions

### Module system
- One `.ml` file per logical concern (fine-grained modules)
- Separate `.mli` for every module; implementation details never leak
- `Ccc_lib` wraps all submodules; users do `open Ccc_lib` or qualified access

### Result type throughout

All fallible operations return `(+'a, +'b) result`. No exceptions for expected
failure modes (empty prompt, arg count mismatch). Only `Sys_error` from the
Unix layer is caught and converted to `Result`-like handling (mapped into a
`Completed_run` with exit code 1).

### No external dependencies
Standard library only: `Unix`, `String`, `List`, `Array`, `Sys`. No Lwt, Async,
or process-management libraries. This keeps the dependency footprint minimal
and the pure logic extraction-friendly.

## 11. Formal Verification Plan

### 11.1 Verification Target Properties

**P1 — Prompt trimming correctness:**
- ∀ s. `trim (trim s) = trim s` (idempotence)
- ∀ s. `trim s = ""` ⟺ `is_whitespace_only s`
- ∀ s, c. `trim s <> ""` ⟹ `s` starts with optional whitespace then `trim s`

**P2 — Exit code invariants (tested, not formally proved):**
- `Completed_run.exit_code` ∈ [0; 255] always (POSIX guarantee from `waitpid`)
- Startup failure path: `exit_code = 1`
- Success path: `exit_code` = child's raw waitpid status

**P3 — Empty rejection completeness:**
- `build_prompt_spec s` returns `Error` ⟺ `trim s = ""`
- `build_prompt_spec s` returns `Ok spec` ⟹ `spec.argv = ["opencode"; "run"; trim s]`

**P4 — Error format structural (tested, simple string concat):**
- `startup_failure argv0 err` = `"failed to start " ^ argv0 ^ ": " ^ err ^ "\n"`
- `startup_failure` never receives the full argv list (type-level guarantee)

**P5 — argv preservation (tested, structural):**
- `Completed_run.argv` = `Command_spec.argv` passed to `run`

### 11.2 Verification Tools and How to Run

**Why3 + Alt-Ergo + CVC5:**

```bash
opam install why3 alt-ergo cvc5
why3 detect           # auto-detect installed provers
why3 prove -P alt-ergo,cvc5 --dir verify prompt_trim
```

The Why3 model is hand-written (`verify/prompt_trim.mlw`) to mirror the OCaml
logic. The OCaml implementation (`verify/prompt_trim.ml`) must match the model
semantically. A compatibility test (`test_verify_compat.ml`) cross-checks the
OCaml and Why3 models on a set of concrete inputs.

**No extraction toolchain needed.** The OCaml code is written to match the
Why3 model by construction. Both are maintained side-by-side.

### 11.3 Scope Boundary

**Verified in Why3 (pure logic):**
- P1: Prompt trimming properties — idempotence, empty equivalence, substring relation
- P3: Empty rejection + argv construction correctness

**Tested via Alcotest (I/O or system-dependent):**
- P2: Exit code handling — `waitpid` return is trusted from the OS
- P4: Error format — trivial string concatenation, tested with concrete cases
- P5: argv preservation — structural invariant, tested in `test_runner.ml`
- Subprocess execution, streaming, `CCC_REAL_OPENCODE` override

### 11.4 Why3 Model

```why3
module PromptTrim

  use string.Char
  use string.String
  use list.List

  predicate is_ws (c: char) =
    c = ' ' \/ c = '\t' \/ c = '\n' \/ c = '\r'

  predicate is_ws_only (s: string) =
    forall i: int. 0 <= i < length s -> is_ws s[i]

  let predicate (==) (a b: string) =
    a = b

  let trim (s: string) : string
    ensures { result = "" <-> is_ws_only s }
    ensures { not (is_ws_only result) }
    ensures { trim result == result }
    ensures { forall i: int. 0 <= i < length result ->
              exists j: int. 0 <= j < length s /\ s[j] = result[i] }
=

  let build_spec (s: string) : option (list string)
    ensures { result = None <-> trim s = "" }
    ensures { match result with
              | Some l -> l = Cons "opencode" (Cons "run" (Cons (trim s) Nil))
              | None -> true
              end }
=

end
```

### 11.5 Verification Workflow

1. Edit `verify/prompt_trim.mlw` (Why3 model) or `verify/prompt_trim.ml` (OCaml impl)
2. Run `why3 prove -P alt-ergo,cvc5 --dir verify prompt_trim`
3. All goals must be proved (green). If any goal times out or fails:
   - Strengthen the model's postconditions, or
   - Fix the OCaml implementation to match
4. Run `dune runtest` to execute `test_verify_compat.ml` (concrete cross-check)
5. Commit both `.mlw` and `.ml` together — they must evolve in lockstep

## 12. Cross-Language Test Registration

The OCaml `ccc` binary must be registered in `tests/test_ccc_contract.py` to
participate in cross-language contract tests. Add the following pattern to each
test method, after the existing Rust/TypeScript/C blocks:

```python
subprocess.run(
    ["dune", "build", "ocaml/bin/ccc.exe"],
    cwd=ROOT,
    capture_output=True,
    text=True,
    check=True,
)
self.assert_equal_output(
    subprocess.run(
        [str(ROOT / "ocaml/_build/default/bin/ccc.exe"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Repeat the analogous pattern for `assert_rejects_empty`,
`assert_rejects_missing_prompt`, and `assert_rejects_whitespace` test methods.

All four test methods in `test_ccc_contract.py` need OCaml registration:
- `test_cross_language_ccc_happy_path`
- `test_cross_language_ccc_rejects_empty_prompt`
- `test_cross_language_ccc_requires_one_prompt_argument`
- `test_cross_language_ccc_rejects_whitespace_only_prompt`

## 13. CI Notes

There is currently no CI configuration in the repository (no `.github/workflows/`).
When CI is added, the OCaml build should include:

```yaml
- name: Install OCaml
  uses: ocaml/setup-ocaml@v2
  with:
    ocaml-compiler: "5.2"

- name: Install dependencies
  run: opam install -y dune alcotest

- name: Build
  run: make -C ocaml build

- name: Test
  run: make -C ocaml test

- name: Verify (Why3)
  run: |
    opam install -y why3 alt-ergo cvc5
    why3 detect
    make -C ocaml verify

- name: Cross-language contract tests
  run: python -m pytest tests/test_ccc_contract.py
```

The cross-language contract tests require `ocaml/bin/ccc.exe` to be built
before running. The dune binary output path is `ocaml/_build/default/bin/ccc.exe`
(Windows-style `.exe` suffix is dune's convention on all platforms).

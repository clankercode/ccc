# OCaml Implementation Plan: call-coding-clis

## 1. Dune Workspace Layout

```
ocaml/
├── dune-project          # (lang dune 3.16)
├── dune                  # workspace root
├── bin/
│   └── dune              # (executable ccc)
│   └── ccc.ml            # CLI entry point
├── lib/
│   └── dune              # (library ccc_lib)
│   ├── command_spec.ml   # CommandSpec type + builder
│   ├── completed_run.ml  # CompletedRun type
│   ├── prompt_spec.ml    # build_prompt_spec (verified module)
│   ├── runner.ml         # Runner: run + stream
│   ├── error_format.ml   # "failed to start <argv[0]>: ..." formatting
│   └── mli/              # separate .mli for every .ml
├── test/
│   └── dune              # (tests)
│   ├── test_prompt_spec.ml
│   ├── test_runner.ml
│   └── test_cli.ml
└── verify/               # Why3 extraction targets
    ├── dune              # (library ccc_verify, no install)
    ├── prompt_trim.ml    # pure extraction-friendly prompt logic
    └── prompt_trim.mli
```

### dune-project

```
(lang dune 3.16)

(package
  (name call-coding-clis)
  (synopsis "OCaml implementation of call-coding-clis")
  (license Unlicense))
```

The `verify/` library is a separate dune library that depends only on pure
logic — no Unix, no I/O — making it suitable for Why3 extraction. The main
`lib/` library re-exports the verified logic under the same API.

## 2. Library API — OCaml Modules and Types

### `Ccc_lib.Command_spec`

```ocaml
type t = {
  argv : string list;
  stdin_text : string option;
  cwd : string option;
  env : (string * string) list;  (* association list; insertion order preserved *)
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
type nonempty_string (* phantom, abstract — inhabited only by strings of length > 0 *)

val build_prompt_spec : string -> (Ccc_lib.Command_spec.t, [> `Empty_prompt]) result
```

The `nonempty_string` phantom type is internal; `build_prompt_spec` returns
`Result.t` with a concrete spec or a `` `Empty_prompt`` error tag. See section 10
for the verified variant.

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
    "failed to start {argv0}: {error}" *)
```

## 3. Subprocess via Unix Module

The default executor uses `Unix.create_process` + `Unix.fork` (or the higher-level
`Unix.open_process_full` variant) to avoid external dependencies:

```
Unix.create_process argv0 argv (Unix.stdin) Unix.stdout Unix.stderr
```

For `run`:
- Fork, redirect child stdout/stderr via `Unix.pipe`, capture via `Unix.read`
- `Unix.waitpid` for exit status
- `Unix.close_process_in` / `Unix.close_process_out` for cleanup
- Catch `Sys_error` on exec failure → produce `Error_format.startup_failure`

For `stream` (v1, buffered):
- Delegate to `run` executor, then invoke callbacks on non-empty stdout/stderr
- Future: use `Unix.select`-driven event loop for true streaming

Environment merging:
- Read `Unix.environment ()`, prepend overrides (later entries shadow earlier)

`CCC_REAL_OPENCODE` env var checked at executor construction time; overrides
`argv0` if present.

## 4. `ccc` CLI Binary

`bin/ccc.ml`:

```
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
matching Rust's `std::process::exit` semantics.

## 5. Prompt Trimming

`String.trim` from the OCaml stdlib strips leading/trailing whitespace
(including Unicode whitespace on 4.x+). The contract:

- `String.trim` applied to any string `s` yields a string `t` such that:
  - `t` is a prefix of `s` followed by a suffix of `s`
  - `t` has no leading or trailing whitespace
  - If `s` is all whitespace, `t = ""`

Empty rejection: after trimming, if the result is `""`, return
`Error `Empty_prompt`.

Formal proof of these properties lives in section 10.

## 6. Error Format — argv[0] Only

On subprocess startup failure (`Sys_error` caught during exec):

```
"failed to start <argv[0]>: <error message>\n"
```

Only `List.hd spec.argv` (or `"(unknown)"` on empty argv) appears. The full
argv is never included in the error string. This is enforced at the type level
by `Error_format.startup_failure` taking a single `string` (the argv0), not a
`string list`.

## 7. Exit Code Forwarding

- Success path: child's raw exit status → `int` via `Unix.waitpid` status
  extraction, forwarded via `Stdlib.exit`.
- Startup failure: exit code 1.
- `Completed_run.exit_code` is always the concrete OS exit status (0–255 on
  POSIX). No normalization.

Invariant proved formally: exit_code ∈ {0, 1} on startup failure path;
exit_code ∈ [0; 255] on normal completion path (guaranteed by OS).

## 8. Test Strategy

### Framework: Alcotest

```
(tests
  (libraries alcotest ccc_lib))
```

### Test categories

**Unit tests (no subprocess):**
- `test_prompt_spec.ml`: empty string, whitespace-only, whitespace-wrapped,
  Unicode whitespace, normal prompt
- `test_error_format.ml`: verify format string contains argv0 and error

**Integration tests (require subprocess):**
- `test_runner.ml`: `CCC_REAL_OPENCODE` override mechanism, nonexistent binary
  → stderr contains "failed to start"
- `test_cli.ml`: arg count validation, empty prompt exit code 1, usage message

**CCC_REAL_OPENCODE handling:**
Tests read the env var and pass it to a `Runner` configured with the overridden
binary. Tests that need a real binary use a trivial `true` or `echo` command
instead.

```
let () =
  let open Alcotest in
  run "ccc_lib"
    [
      ("prompt_spec", [
        test_case "empty prompt rejected" `Quick (fun () ->
          let res = Ccc_lib.Prompt_spec.build_prompt_spec "" in
          check (result string string) "empty" (Error `Empty_prompt) res);
        test_case "whitespace trimmed" `Quick (fun () ->
          let spec = Ccc_lib.Prompt_spec.build_prompt_spec "  hello  " in
          check (result string (list string)) "argv" (Ok ["opencode"; "run"; "hello"])
            (Result.map (fun s -> s.argv) spec));
      ]);
      ("runner", [...]);
      ("cli", [...]);
    ]
```

## 9. OCaml-Specific Design Decisions

### Module system
- One `.ml` file per logical concern (fine-grained modules)
- Separate `.mli` for every module; implementation details never leak
- `Ccc_lib` wraps all submodules; users do `open Ccc_lib` or qualified access

### GADTs for stream event routing

```ocaml
type _ stream_channel =
  | Stdout : string stream_channel
  | Stderr : string stream_channel

type stream_event =
  | Event : 'a stream_channel * string -> stream_event
```

The `Stream_callback` type is `(string -> string -> unit)` for simplicity
(tag + payload), matching the cross-language contract.

### Result type throughout

All fallible operations return `(+'a, +'b) result`. No exceptions for expected
failure modes (empty prompt, arg count mismatch). Only `Sys_error` from the
Unix layer is caught and converted to `Result`.

### Phantom types for invalid-state elimination

```ocaml
type 'a prompt_status =
  | Unverified : string prompt_status
  | Trimmed : string prompt_status
  | Nonempty : nonempty_string prompt_status  (* GADT: only inhabited after proof *)

type spec_builder : 'a prompt_status -> string -> 'b prompt_status option
```

In practice, `build_prompt_spec` collapses this into a single `Result` return
since the intermediate states are internal. The phantom type machinery exists
primarily for the verification layer (section 10).

## 10. Formal Verification Plan

### 10.1 Verification Target Properties

**P1 — Prompt trimming correctness:**
- ∀ s. `String.trim (String.trim s) = String.trim s`  (idempotence)
- ∀ s. `String.trim s = ""` ⟺ `is_whitespace_only s`
- ∀ s. `String.trim s <> ""` ⟹ `List.hd (String.trim s :: _)` is the first
  non-whitespace character of `s`

**P2 — Exit code invariants:**
- `Completed_run.exit_code` ∈ [0; 255] always (POSIX constraint)
- Startup failure path: `exit_code = 1` ∧ `stderr` starts with `"failed to start "`
- Success path: `exit_code` = child's raw waitpid status

**P3 — Empty rejection completeness:**
- `build_prompt_spec s` returns `Error` ⟺ `String.trim s = ""`
- `build_prompt_spec s` returns `Ok spec` ⟹ `spec.argv = ["opencode"; "run"; String.trim s]`

**P4 — Error format structural:**
- `startup_failure argv0 err` starts with `"failed to start "` and contains `argv0`
- `startup_failure` never receives the full argv list (type-level guarantee)

**P5 — argv preservation:**
- `Completed_run.argv` = `Command_spec.argv` passed to `run` (identity invariant)

### 10.2 Verification Tools

**Why3 + Alt-Ergo** (primary):
- Extract pure logic from `verify/prompt_trim.ml` to Why3 via `js_of_ocaml`
  or manual extraction
- Prove P1, P3 in Why3; discharge goals with Alt-Ergo + CVC5
- Why3 goals written as `.mlw` files checked into `verify/`

**Extraction strategy:**
- `verify/prompt_trim.ml` contains the prompt logic using only `String` and
  `List` operations — no I/O, no Unix, no exceptions
- This module is compiled separately as `ccc_verify` library
- The main `lib/prompt_spec.ml` calls into it (or is a thin wrapper)
- Manual Why3 models (`verify/prompt_trim.mlw`) mirror the OCaml logic;
  CI runs `why3 prove` to check all goals remain valid

### 10.3 Phantom Types and GADTs for Invalid-State Elimination

```ocaml
type nonempty = private Nonempty

module String : sig
  type t = private string

  val of_string_exn : string -> t
  (** Raises if string is empty after trimming. *)

  val to_string : t -> string
  (** Embedding: every nonempty string is a string. *)

  val trim_preserves_nonempty : t -> t
  (** Verified: trimming a known-nonempty string cannot produce empty.
      In practice, trimming "a" gives "a"; trimming " a " gives "a".
      Only proven for ASCII whitespace in the Why3 model. *)
end
```

The `nonempty` phantom type ensures that a value of type `String.t` can never
represent an empty string — the constructor is private. The only way to produce
one is `of_string_exn`, which checks the precondition. After that, all
downstream code can assume non-emptiness without further checks.

**GADT witness for verified spec:**

```ocaml
type _ verified = Verified : 'a verified

type t = {
  argv : string list;
  stdin_text : string option;
  cwd : string option;
  env : (string * string) list;
}
and spec_status =
  | Raw : t spec_status
  | With_prompt : (t * String.t) spec_status

val build : string -> (t * String.t, [> `Empty_prompt]) result
(** Returns [Ok (spec, trimmed)] only when [trimmed] is provably nonempty. *)
```

### 10.4 Verification Workflow

```
verify/
├── prompt_trim.mlw        # Why3 model (hand-written, mirrors OCaml)
├── prompt_trim.ml         # OCaml extraction-friendly implementation
├── prompt_trim.mli        # Signature with phantom types
├── test_verify_compat.ml  # Alcotest: OCaml ↔ Why3 model cross-check
└── dune                   # (library ccc_verify)

# CI step:
why3 prove -P alt-ergo,cvc5 verify/prompt_trim.mlw
```

### 10.5 Scope Boundary for Verification

Verified in Why3:
- Prompt trimming properties (P1, P3) — pure string logic
- Empty rejection completeness (P3)
- Error format structure (P4) — string concatenation properties

Not verified (too much I/O/system interaction; tested via Alcotest):
- Subprocess execution (P2 success path)
- Exit code range (P2) — trusted from Unix.waitpid
- Streaming behavior
- argv preservation through the runner (P5) — structural, tested in unit tests

The verification boundary is drawn at the pure/side-effecting frontier. All
pure logic that could affect correctness (prompt normalization, empty checks,
error formatting) is formally proved. All I/O-bound behavior is tested
traditionally with Alcotest + `CCC_REAL_OPENCODE`.

### 10.6 Why3 Model Sketch

```why3
module PromptTrim

  use string.Char
  use string.String

  predicate is_whitespace (c: char) =
    c = ' ' \/ c = '\t' \/ c = '\n' \/ c = '\r'

  predicate is_whitespace_only (s: string) =
    forall i: int. 0 <= i < length s -> is_whitespace s[i]

  let trim (s: string) : string
    ensures { forall i: int. 0 <= i < length result ->
              exists j: int. 0 <= j < length s /\ s[j] = result[i] }
    ensures { is_whitespace_only (s ++ result ++ "") -> false }
    ensures { result = "" <-> is_whitespace_only s }
    ensures { trim result = result }

  let build_prompt_spec (s: string) : option (list string)
    ensures { result = None <-> trim s = "" }
    ensures { match result with
              | Some argv -> argv = Cons "opencode" (Cons "run" (Cons (trim s) Nil))
              | None -> true
              end }

end
```

This is the target for `why3 prove`. The OCaml implementation in
`verify/prompt_trim.ml` must be provably equivalent under the same
preconditions.

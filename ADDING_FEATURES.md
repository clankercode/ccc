# Adding Features

This repo now has a preferred rollout order for cross-implementation features.

## Required Invariants

These are not optional for shared CLI/library changes:

1. Implement the change in Python.
2. Implement the same change in Rust.
3. Update the relevant docs to describe the new feature, fix, or semantic change.
4. Update the shared cross-implementation tests to account for the change.
5. Update [SHARED_CHANGES.md](/home/xertrov/src/call-coding-clis/SHARED_CHANGES.md) with a short entry describing the feature, fix, or semantic change.
6. Run the targeted Python and Rust tests.
7. Run `just install-rs` after the Rust update so the installed local `ccc` matches the tested Rust implementation.

If step 5 is missing, the feature is not ready to land.

Updating the other language implementations is encouraged, but optional unless the task explicitly calls for a broader rollout.

## Default Flow

When a change is intended to roll out beyond Python and Rust:

1. Implement the feature in Python first.
2. Implement the same feature in Rust second.
3. Update the relevant docs, the shared cross-implementation tests, and `SHARED_CHANGES.md`.
4. Run the targeted Python and Rust tests.
5. Run the shared cross-implementation contract tests.
6. Only after Python and Rust are working, optionally update the remaining languages with subagents.
7. Re-run targeted per-language tests plus the shared contract suite.

## Why Python First

- Python is the fastest reference path for parser/config/help changes.
- The parser/config tests are small and quick to iterate on.
- It is the easiest place to lock down semantics before pushing them across the repo.

## Why Rust Second

- Rust is the main library implementation used by other local tooling.
- Keeping Rust close to Python prevents the repo from splitting into "reference semantics" and "production semantics".

## Minimum Test Sequence

Every shared feature or fix must include:
- doc updates for the user-facing or maintainer-facing behavior that changed
- cross-implementation test updates
- a `SHARED_CHANGES.md` entry written before finalizing the work

Do not land a shared semantic change without adjusting the docs, updating the contract or harness coverage that should detect it, and recording the semantic change in `SHARED_CHANGES.md`.

For Python changes:

```bash
PYTHONPATH=python python3 -m unittest tests.test_parser_config -v
PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Python -v
```

For Rust changes:

```bash
cd rust && cargo test
PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v
```

After Python and Rust are both updated:

```bash
PYTHONPATH=python python3 -m unittest tests.test_ccc_contract -v
PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Python -v
PYTHONPATH=. python3 tests/test_ccc_contract_impl.py Rust -v
```

If the feature affects runner execution behavior, also run the targeted Python and Rust harness checks:

```bash
PYTHONPATH=. python3 tests/test_harness.py Python -v
PYTHONPATH=. python3 tests/test_harness.py Rust -v
```

Only run the `all` cross-implementation suite when you are explicitly rolling the change beyond Python and Rust.

## Subagent Phase

Once Python and Rust are green:

- decide explicitly whether the remaining languages should be updated now or deferred
- dispatch one subagent per language, unless two languages are close enough that a shared worker is clearly cheaper
- prefer `gpt-5.4-mini` with `xhigh` reasoning for these language-specific rollout workers
- give each subagent ownership of one language directory only
- tell each subagent not to revert unrelated edits
- require the smallest relevant unit/spec tests first
- require `PYTHONPATH=. python3 tests/test_ccc_contract_impl.py <Language> -v`

Typical subagent prompt requirements:

- state the exact semantic change
- list the owned files/directories
- forbid edits outside that language implementation
- remind the worker that shared tests were already updated and the language-specific work must match that contract
- remind the worker that docs and `SHARED_CHANGES.md` are required at the main rollout level even if that worker does not own them
- require a short test summary with exact commands

## Contract Tests

- `tests/test_ccc_contract_impl.py` is the maintained cross-implementation CLI contract suite
- `tests/test_ccc_contract.py` is a compatibility wrapper over that maintained suite
- `tests/test_harness.py` is the mock-runner behavior harness

When adding a new shared CLI feature, prefer extending `tests/test_ccc_contract_impl.py` instead of duplicating logic elsewhere.

If the change affects subprocess execution behavior, stdin behavior, env behavior, or runner command shape, update `tests/test_harness.py` or the relevant shared harness coverage too.

## Shared Change Log

- `SHARED_CHANGES.md` is the required ledger for shared features, fixes, and semantic changes
- updating `SHARED_CHANGES.md` is a release-blocking requirement for any shared semantic change
- every shared change must add a short dated entry with:
  - what changed
  - which docs were updated
  - whether the change is Python+Rust only or rolled out further
  - which shared tests were updated
- this file is the source of truth for what has landed semantically, even when some implementations are still catching up

Before sending a final "implemented" response for a shared feature, explicitly verify that `SHARED_CHANGES.md` is in the modified file set.

## Practical Rule

Do not start broad multi-language rollout until Python and Rust both express the final intended semantics, the docs have been updated, the shared tests have been updated, `SHARED_CHANGES.md` has been updated, and the targeted Python/Rust tests are green.

Always run `just install-rs` after updating Rust so the installed local `ccc` binary matches the tested implementation.

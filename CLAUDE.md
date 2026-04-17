Note: `cc` is an alias for claude code. If you need a c compiler, use absolute paths or a different tool. 

When working on one implementation, do not default to `./run_all_tests.sh`. Use `./test_impl.sh <language>` so you only run that implementation's unit tests plus the targeted cross-language contract and harness checks.

Examples:
- `./test_impl.sh c`
- `./test_impl.sh rust`
- `PYTHONPATH=python python3 tests/test_harness.py c -v`
- `PYTHONPATH=python python3 tests/test_ccc_contract_impl.py c -v`

Use `./run_all_tests.sh` only when you intentionally want the whole repository sweep. `tests/test_harness.py` now requires an explicit language or `all` when run directly.

When adding or modifying CLI command assembly in code, always check the real CLI directly with the actual binary and flags, not just tests or help text. Use direct smoke tests to confirm the argv shape still works end-to-end.

When editing markdown files in this repo, use relative markdown links rather than absolute filesystem paths.

Incomplete work is tracked in [`TASKS.md`](TASKS.md) at the repo root and in each language's `PLAN.md` file for implementation-specific follow-ups.

Shared feature changes that still need rollout to other implementations are noted in [`SHARED_CHANGES.md`](SHARED_CHANGES.md) under `Additional rollout`; use that file as follow-up context, not as the authoritative backlog.

When changing the behavior of `ccc` in any way, including feature work and bug fixes, read [`ADDING_FEATURES.md`](ADDING_FEATURES.md) first.

When adding config fields, update any generated config example/schema output and the related docs at the same time.

Always prefer cross-impl tests rather than language-specific tests.
Language-specific tests are for language specific behavior or quirks.
When running cross-impl tests, run them only for the languages you're concerned with; running all of them is not advised nor necessary. 

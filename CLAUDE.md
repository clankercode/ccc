Note: `cc` is an alias for claude code. If you need a c compiler, use absolute paths or a different tool. 

When working on one implementation, do not default to `./run_all_tests.sh`. Use `./test_impl.sh <language>` so you only run that implementation's unit tests plus the targeted cross-language contract and harness checks.

Examples:
- `./test_impl.sh c`
- `./test_impl.sh rust`
- `PYTHONPATH=python python3 tests/test_harness.py c -v`
- `PYTHONPATH=python python3 tests/test_ccc_contract_impl.py c -v`

Use `./run_all_tests.sh` only when you intentionally want the whole repository sweep. `tests/test_harness.py` now requires an explicit language or `all` when run directly.

When adding or modifying CLI command assembly in code, always check the real CLI directly with the actual binary and flags, not just tests or help text. Use direct smoke tests to confirm the argv shape still works end-to-end.

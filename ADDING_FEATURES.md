# Adding Features

This repo now has a preferred rollout order for cross-implementation features.

## Default Flow

1. Implement the feature in Python first.
2. Implement the same feature in Rust second.
3. Run the targeted Python and Rust tests.
4. Run the shared cross-implementation contract tests.
5. Only after Python and Rust are working, update the remaining languages with subagents.
6. Re-run targeted per-language tests plus the shared contract suite.

## Why Python First

- Python is the fastest reference path for parser/config/help changes.
- The parser/config tests are small and quick to iterate on.
- It is the easiest place to lock down semantics before pushing them across the repo.

## Why Rust Second

- Rust is the main library implementation used by other local tooling.
- Keeping Rust close to Python prevents the repo from splitting into "reference semantics" and "production semantics".

## Minimum Test Sequence

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
PYTHONPATH=. python3 tests/test_ccc_contract_impl.py all -v
```

If the feature affects runner execution behavior, also run:

```bash
PYTHONPATH=. python3 tests/test_harness.py <language> -v
```

or:

```bash
PYTHONPATH=. python3 tests/test_harness.py all -v
```

## Subagent Phase

Once Python and Rust are green:

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
- require a short test summary with exact commands

## Contract Tests

- `tests/test_ccc_contract_impl.py` is the maintained cross-implementation CLI contract suite
- `tests/test_ccc_contract.py` is a compatibility wrapper over that maintained suite
- `tests/test_harness.py` is the mock-runner behavior harness

When adding a new shared CLI feature, prefer extending `tests/test_ccc_contract_impl.py` instead of duplicating logic elsewhere.

## Practical Rule

Do not start broad multi-language rollout until Python and Rust both express the final intended semantics and have passing targeted tests.

Always run `just install-rs` after updating Rust so the installed local `ccc` binary matches the tested implementation.

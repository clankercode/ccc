# Mock Smoke Recipes

These recipes are for local visual checks when you want `ccc` to run against a mock binary instead of the real upstream CLI.

## Shared Env Overrides

Python and Rust support these env overrides:

- `CCC_REAL_OPENCODE`
- `CCC_REAL_CLAUDE`
- `CCC_REAL_KIMI`
- `CCC_REAL_CURSOR`

They replace the selected runner binary directly without needing temporary `PATH` symlinks.

## Claude Formatted Smoke

Use the mock Claude runner directly with formatted output:

```sh
env \
  MOCK_JSON_SCHEMA=claude-code \
  CCC_REAL_CLAUDE="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  rust/target/debug/ccc cc .fmt "osc test"
```

Disable sanitization to confirm the raw OSC title sequence is still present:

```sh
env \
  MOCK_JSON_SCHEMA=claude-code \
  CCC_REAL_CLAUDE="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  rust/target/debug/ccc cc .fmt --no-sanitize-osc "osc test"
```

Python is equivalent:

```sh
env \
  MOCK_JSON_SCHEMA=claude-code \
  CCC_REAL_CLAUDE="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  python3 python/call_coding_clis/cli.py cc .fmt "osc test"
```

## Kimi Formatted Smoke

```sh
env \
  MOCK_JSON_SCHEMA=kimi-code \
  CCC_REAL_KIMI="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  rust/target/debug/ccc k ..fmt "thinking"
```

## Cursor Formatted Smoke

```sh
env \
  MOCK_JSON_SCHEMA=cursor-agent \
  CCC_REAL_CURSOR="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  rust/target/debug/ccc cu .fmt "tool call"
```

## Raw OpenCode JSON Smoke

```sh
env \
  MOCK_JSON_SCHEMA=opencode \
  CCC_REAL_OPENCODE="$PWD/tests/mock-coding-cli/mock_coding_cli.sh" \
  rust/target/debug/ccc oc .json "hello world"
```

## Notes

- The mock runner reads stdin when it is open. For ad hoc shell experiments, redirect stdin from `/dev/null` if your shell or wrapper keeps stdin open.
- `scripts/smoke-output-modes.sh` is still the preferred real-runner smoke script. This file is for controlled mock-based debugging and renderer inspection.

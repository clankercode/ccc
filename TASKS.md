# TASKS

Living backlog of unfinished work. Completed items should move to `SHARED_CHANGES.md`, `FEATURES.md`, or the relevant feature docs.

- [ ] Add a config option and CLI flag to strip disruptive OSC codes from human-facing output
  - Preserve OSC 8 hyperlinks.
  - Strip bells, title changes, and other terminal side effects that should not leak into text output.
  - Wire the behavior through Python and Rust first, then propagate it to other implementations where applicable.
  - Add tests for raw-output sanitization and real CLI smoke checks.
- [ ] Finish `--allow-tool` / `--deny-tool` support where the upstream CLI can express it
  - Start with Claude and OpenCode.
  - Keep the permission-mapping matrix in `docs/clis/README.md` current.
  - Warn or ignore on runners that only have coarse-grained approval modes.
- [ ] Keep `docs/clis/model-capabilities.json` current as new models land
  - Refresh `opencode models` snapshots when auth-scoped inventories change.
  - Smoke-test representative cheap routes before updating normalized entries.
- [ ] Expand `--permission-mode` mappings only where the upstream CLI surface is honest
  - Prefer runner-native flags and config over invented parity.
  - Document unsupported cases explicitly.
- [ ] Review and prune stale roadmap items in per-language `PLAN.md` files
  - Fold completed work into the main docs.
  - Keep the remaining plan items focused on actual open work.
- [ ] Decide whether structured output rendering needs templating or user customization
  - This is the `v2` rendering direction currently noted in `README.md`.
  - Keep the scope narrow unless there is a concrete user-facing need.

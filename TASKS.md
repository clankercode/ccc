# TASKS

Living backlog of unfinished work. Completed items should move to `SHARED_CHANGES.md`, `FEATURES.md`, or the relevant feature docs.

- [ ] Finish `--allow-tool` / `--deny-tool` support where the upstream CLI can express it
  - Start with Claude and OpenCode.
  - Keep the permission-mapping matrix in `docs/clis/README.md` current.
  - Warn or ignore on runners that only have coarse-grained approval modes.
- [ ] Keep `docs/clis/model-capabilities.json` current as new models land
  - Refresh `opencode models` snapshots when auth-scoped inventories change.
  - Smoke-test representative cheap routes before updating normalized entries.
- [ ] Review and prune stale roadmap items in per-language `PLAN.md` files
  - Fold completed work into the main docs.
  - Keep the remaining plan items focused on actual open work.
- [ ] Add a repo-root `VERSION` file and pull it into implementations at build time
  - Use it as the single source of truth for reported package/CLI version strings where feasible.
  - Keep the language-specific build/release flow honest about when the baked-in version is refreshed.
- [ ] Decide whether structured output rendering needs templating or user customization
  - This is the `v2` rendering direction currently noted in `README.md`.
  - Keep the scope narrow unless there is a concrete user-facing need.

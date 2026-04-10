# TASKS

Living backlog of unfinished work. Completed items should move to `SHARED_CHANGES.md`, `FEATURES.md`, or the relevant feature docs.

- [ ] Support a `ccc config` command that prints the local user config's location and contents
  - Print the resolved config file path (respecting `CCC_CONFIG` env var and default locations).
  - Output the full config contents (raw or pretty-printed JSON) to stdout.
  - Exit non-zero if no config file is found, with a helpful message.
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
- [ ] Add multi-provider / multi-preset / multi-alias routing based on capacity, usage, and round-robin policy
  - Allow a single logical route to fan out across multiple providers, presets, aliases, or equivalent backends.
  - Detect `429` rate-limit responses and other retryable provider errors, then fail over or rotate according to policy.
  - Track enough usage/capacity state to avoid hammering an exhausted route and to make round-robin selection stable.
- [ ] Capture real Kimi rate-limit and provider-error samples across every surface `ccc` reads
  - Collect representative `429` and nearby failure cases from plain stdout/stderr, `json`, and `stream-json` modes.
  - Save the observed payloads and transcripts in the same fixture style used for other real runner captures so parser and retry logic can target actual shapes.
  - Note which signals are stable enough for automated detection versus human-facing text that should stay best-effort only.

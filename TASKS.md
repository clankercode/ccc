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
- [ ] Add multi-provider / multi-preset / multi-alias routing based on capacity, usage, and round-robin policy
  - Allow a single logical route to fan out across multiple providers, presets, aliases, or equivalent backends.
  - Detect `429` rate-limit responses and other retryable provider errors, then fail over or rotate according to policy.
  - Track enough usage/capacity state to avoid hammering an exhausted route and to make round-robin selection stable.
- [ ] Graceful fallback when configured output_mode is unsupported by the selected runner
  - Reproduce: set `output_mode = "stream-formatted"` in `[defaults]` of `~/.config/ccc/config.toml`, then run with `@gpt54` (runner = "c", codex). Result: `runner does not support requested output mode` hard error, exit 1.
  - `NO_COLOR=1` does not help — it only affects TTY detection, not an explicitly configured output_mode.
  - Expected: warn and fall back to `text` (or `stream-text`) rather than hard-failing, so programmatic callers and aliases that don't override output_mode still work.
  - Workaround: callers (e.g. looper) must explicitly pass `-o text` on every invocation to override the global config.
- [ ] Capture real Kimi rate-limit and provider-error samples across every surface `ccc` reads
  - Collect representative `429` and nearby failure cases from plain stdout/stderr, `json`, and `stream-json` modes.
  - Save the observed payloads and transcripts in the same fixture style used for other real runner captures so parser and retry logic can target actual shapes.
  - Note which signals are stable enough for automated detection versus human-facing text that should stay best-effort only.

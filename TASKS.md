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
- [ ] Decide whether structured output rendering needs templating or user customization
  - This is the `v2` rendering direction currently noted in `README.md`.
  - Keep the scope narrow unless there is a concrete user-facing need.
- [ ] Eventually default `CCC_FWD_UNKNOWN_JSON` back to false
  - The environment-controlled default is temporarily true so parser gaps stay visible during structured-output hardening.
  - Keep run artifacts recording unknown JSON regardless of the forwarding default.
  - Deferred indefinitely until structured output coverage is boring enough that hidden terminal forwarding is acceptable.
- [ ] Add multi-provider / multi-preset / multi-alias routing based on capacity, usage, and round-robin policy
  - Allow a single logical route to fan out across multiple providers, presets, aliases, or equivalent backends.
  - Detect `429` rate-limit responses and other retryable provider errors, then fail over or rotate according to policy.
  - Track enough usage/capacity state to avoid hammering an exhausted route and to make round-robin selection stable.
- [ ] Support failover aliases as an ordered sequence of aliases to try if the first one fails
  - Keep the first alias as the primary route, then fall through to the next configured alias on failure.
  - Reuse the same failure signals as the provider-routing work so the behavior stays consistent.
  - Make the fallback order explicit in config/docs rather than inferring it from naming.
- [ ] Capture real Kimi rate-limit and provider-error samples across every surface `ccc` reads
  - Collect representative `429` and nearby failure cases from plain stdout/stderr, `json`, and `stream-json` modes.
  - Save the observed payloads and transcripts in the same fixture style used for other real runner captures so parser and retry logic can target actual shapes.
  - Note which signals are stable enough for automated detection versus human-facing text that should stay best-effort only.
- [ ] Add HTTP/HTTPS delivery for final-message sinks
  - Keep the first pass focused on local file and stdio destinations for scripts.
  - Reuse the final-output sink abstraction so remote delivery can land later without changing the CLI surface again.
- [] do something with tests/fixtures/unhandled-claude-json.txt

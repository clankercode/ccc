# Primary Goal

Achieve complete feature coverage across all 20 languages for call-coding-clis: v1 core features, v2 parser/config features, v3 JSON output parsing, plus comprehensive testing infrastructure.

## Acceptance Criteria

### Phase 1: Foundation & v1 Verification
- [x] FEATURES.md tracks all features for all 20 languages
- [x] JSON fixture files exist for claude-code, kimi-code, opencode schemas
- [x] MOCK_CODING_CLI_PLAN.md exists and is current
- [x] All 8 active languages pass all existing tests (unit + contract + harness)
- [x] v1 feature gaps identified and fixed for all 8 active languages
- [x] Mock coding CLI supports JSON output via MOCK_JSON_SCHEMA env var
- [x] All foundation work committed

### Phase 2: Remaining 12 Languages
- [x] All 12 planned languages scaffolded with v1 features
- [x] Each new language has: CommandSpec, CompletedRun, Runner.run, Runner.stream, ccc CLI, build_prompt_spec, prompt trimming, empty rejection, stdin/cwd/env, startup failure, exit code forwarding, CCC_REAL_OPENCODE
- [x] Each new language has unit tests
- [ ] Each new language passes contract tests
- [ ] Each new language passes harness tests
- [x] FEATURES.md updated with all new languages
- [ ] run_all_tests.sh updated for all new languages

### Phase 3: v2 Parser/Config Features
- [ ] Parser/config design finalized in CCC_PARSER_CONFIG_DESIGN.md
- [ ] Runner selector (F16) implemented in all 20 languages
- [ ] Thinking level (F17) implemented in all 20 languages
- [ ] Provider/model selector (F18) implemented in all 20 languages
- [ ] Alias/preset (F19) implemented in all 20 languages
- [ ] Config file loading (F20) implemented in all 20 languages
- [ ] FEATURES.md updated

### Phase 4: v3 JSON Output Parsing
- [ ] JSON output parsing (F23) implemented in all 20 languages
- [ ] OpenCode schema (F24) support in all 20 languages
- [ ] Claude Code schema (F25) support in all 20 languages
- [ ] Kimi schema (F26) support in all 20 languages
- [ ] JSON render (F27) implemented in all 20 languages
- [ ] Mock e2e JSON fixture tests pass for all languages
- [ ] FEATURES.md updated

### Cross-cutting
- [ ] Parallel comparison runner script/tool exists
- [ ] Frequent commits throughout

## Current Status
- Iteration: 3
- Newly satisfied: Phase 1 complete, Phase 2 scaffolding complete
- Remaining: Wire new 12 languages into contract/harness tests, Phase 3, Phase 4

## Current Plan
- Phase 2 mostly done — need to wire new languages into test harness and contract tests
- Next: add new languages to test_ccc_contract.py and test_harness.py
- Then: build parallel comparison runner

## Blockers / Notes
- OpenCode archived (moved to Crush) — trivial JSON schema
- PureScript needs spago toolchain to compile
- VBScript Windows-only (can't test on Linux)
- ASM no libc — no stdin/cwd/env
- Some build artifacts accidentally committed (need cleanup)

## ON_GOAL_COMPLETE_NEXT_STEPS
When all phases are satisfied, review the entire codebase for consistency, update all documentation, and report completion.

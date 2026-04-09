import os
import unittest
import tempfile
from pathlib import Path
from unittest import mock

from call_coding_clis.parser import (
    parse_args,
    resolve_command,
    resolve_output_mode,
    resolve_output_plan,
    resolve_sanitize_osc,
    resolve_show_thinking,
    ParsedArgs,
    CccConfig,
    AliasDef,
    RUNNER_REGISTRY,
)
from call_coding_clis.config import load_config


class ParseArgsTests(unittest.TestCase):
    def test_prompt_only(self):
        parsed = parse_args(["hello world"])
        self.assertEqual(parsed.prompt, "hello world")
        self.assertIsNone(parsed.runner)
        self.assertIsNone(parsed.thinking)
        self.assertIsNone(parsed.show_thinking)
        self.assertIsNone(parsed.sanitize_osc)
        self.assertFalse(parsed.yolo)
        self.assertIsNone(parsed.permission_mode)
        self.assertIsNone(parsed.provider)
        self.assertIsNone(parsed.model)
        self.assertIsNone(parsed.alias)

    def test_runner_selector_cc(self):
        parsed = parse_args(["cc", "fix bug"])
        self.assertEqual(parsed.runner, "cc")
        self.assertEqual(parsed.prompt, "fix bug")

    def test_runner_selector_c(self):
        parsed = parse_args(["c", "fix bug"])
        self.assertEqual(parsed.runner, "c")
        self.assertEqual(parsed.prompt, "fix bug")

    def test_runner_selector_cx(self):
        parsed = parse_args(["cx", "fix bug"])
        self.assertEqual(parsed.runner, "cx")
        self.assertEqual(parsed.prompt, "fix bug")

    def test_runner_selector_opencode(self):
        parsed = parse_args(["opencode", "hello"])
        self.assertEqual(parsed.runner, "opencode")
        self.assertEqual(parsed.prompt, "hello")

    def test_thinking_level(self):
        parsed = parse_args(["+2", "hello"])
        self.assertEqual(parsed.thinking, 2)
        self.assertEqual(parsed.prompt, "hello")

    def test_named_thinking_levels(self):
        cases = {
            "+none": 0,
            "+low": 1,
            "+med": 2,
            "+mid": 2,
            "+medium": 2,
            "+3": 3,
            "+high": 3,
            "+4": 4,
            "+max": 4,
            "+xhigh": 4,
        }
        for token, expected in cases.items():
            with self.subTest(token=token):
                parsed = parse_args([token, "hello"])
                self.assertEqual(parsed.thinking, expected)
                self.assertEqual(parsed.prompt, "hello")

    def test_provider_model(self):
        parsed = parse_args([":anthropic:claude-4", "hello"])
        self.assertEqual(parsed.provider, "anthropic")
        self.assertEqual(parsed.model, "claude-4")
        self.assertEqual(parsed.prompt, "hello")

    def test_model_only(self):
        parsed = parse_args([":gpt-4o", "hello"])
        self.assertEqual(parsed.model, "gpt-4o")
        self.assertIsNone(parsed.provider)
        self.assertEqual(parsed.prompt, "hello")

    def test_alias(self):
        parsed = parse_args(["@work", "hello"])
        self.assertEqual(parsed.alias, "work")
        self.assertEqual(parsed.prompt, "hello")

    def test_output_mode_flag(self):
        parsed = parse_args(["-o", "stream-formatted", "hello"])
        self.assertEqual(parsed.output_mode, "stream-formatted")
        self.assertEqual(parsed.prompt, "hello")

    def test_output_mode_sugar(self):
        cases = {
            ".text": "text",
            "..text": "stream-text",
            ".json": "json",
            "..json": "stream-json",
            ".fmt": "formatted",
            "..fmt": "stream-formatted",
        }
        for token, expected in cases.items():
            with self.subTest(token=token):
                parsed = parse_args([token, "hello"])
                self.assertEqual(parsed.output_mode, expected)
                self.assertEqual(parsed.prompt, "hello")

    def test_forward_unknown_json_flag(self):
        parsed = parse_args(["--forward-unknown-json", "hello"])
        self.assertTrue(parsed.forward_unknown_json)

    def test_full_combo(self):
        parsed = parse_args(
            ["cc", "--yolo", "+3", ":anthropic:claude-4", "@fast", "fix tests"]
        )
        self.assertEqual(parsed.runner, "cc")
        self.assertEqual(parsed.thinking, 3)
        self.assertTrue(parsed.yolo)
        self.assertEqual(parsed.permission_mode, "yolo")
        self.assertEqual(parsed.provider, "anthropic")
        self.assertEqual(parsed.model, "claude-4")
        self.assertEqual(parsed.alias, "fast")
        self.assertEqual(parsed.prompt, "fix tests")

    def test_runner_case_insensitive(self):
        parsed = parse_args(["CC", "hello"])
        self.assertEqual(parsed.runner, "cc")

    def test_thinking_zero(self):
        parsed = parse_args(["+0", "hello"])
        self.assertEqual(parsed.thinking, 0)

    def test_show_thinking_flag(self):
        parsed = parse_args(["--show-thinking", "hello"])
        self.assertTrue(parsed.show_thinking)
        self.assertEqual(parsed.prompt, "hello")

    def test_no_show_thinking_flag(self):
        parsed = parse_args(["--no-show-thinking", "hello"])
        self.assertFalse(parsed.show_thinking)
        self.assertEqual(parsed.prompt, "hello")

    def test_sanitize_osc_flag(self):
        parsed = parse_args(["--sanitize-osc", "hello"])
        self.assertTrue(parsed.sanitize_osc)
        self.assertEqual(parsed.prompt, "hello")

    def test_no_sanitize_osc_flag(self):
        parsed = parse_args(["--no-sanitize-osc", "hello"])
        self.assertFalse(parsed.sanitize_osc)
        self.assertEqual(parsed.prompt, "hello")

    def test_yolo_flags(self):
        for token in ("--yolo", "-y"):
            with self.subTest(token=token):
                parsed = parse_args([token, "hello"])
                self.assertTrue(parsed.yolo)
                self.assertEqual(parsed.permission_mode, "yolo")
                self.assertEqual(parsed.prompt, "hello")

    def test_permission_mode_flag(self):
        parsed = parse_args(["--permission-mode", "auto", "hello"])
        self.assertEqual(parsed.permission_mode, "auto")
        self.assertFalse(parsed.yolo)
        self.assertEqual(parsed.prompt, "hello")

    def test_permission_mode_yolo_sets_yolo(self):
        parsed = parse_args(["--permission-mode", "yolo", "hello"])
        self.assertEqual(parsed.permission_mode, "yolo")
        self.assertTrue(parsed.yolo)

    def test_permission_mode_last_wins_over_yolo_sugar(self):
        parsed = parse_args(["--yolo", "--permission-mode", "safe", "hello"])
        self.assertEqual(parsed.permission_mode, "safe")
        self.assertFalse(parsed.yolo)
        self.assertEqual(parsed.prompt, "hello")

    def test_control_tokens_can_appear_in_any_order(self):
        parsed = parse_args(
            ["@fast", ":anthropic:claude-4", "--yolo", "cc", "+3", "fix tests"]
        )
        self.assertEqual(parsed.runner, "cc")
        self.assertEqual(parsed.thinking, 3)
        self.assertTrue(parsed.yolo)
        self.assertEqual(parsed.permission_mode, "yolo")
        self.assertEqual(parsed.provider, "anthropic")
        self.assertEqual(parsed.model, "claude-4")
        self.assertEqual(parsed.alias, "fast")
        self.assertEqual(parsed.prompt, "fix tests")

    def test_duplicate_pre_prompt_controls_use_last_value(self):
        parsed = parse_args(
            ["cc", "k", "--show-thinking", "--no-show-thinking", "@fast", "@slow", "hello"]
        )
        self.assertEqual(parsed.runner, "k")
        self.assertFalse(parsed.show_thinking)
        self.assertEqual(parsed.alias, "slow")
        self.assertEqual(parsed.prompt, "hello")

    def test_double_dash_forces_literal_prompt(self):
        parsed = parse_args(["-y", "--", "+1", "@agent", ":model"])
        self.assertTrue(parsed.yolo)
        self.assertEqual(parsed.prompt, "+1 @agent :model")

    def test_permission_mode_missing_value_errors_in_resolve(self):
        parsed = parse_args(["--permission-mode"])
        self.assertEqual(parsed.permission_mode, "")
        with self.assertRaises(ValueError):
            resolve_command(parsed)

    def test_thinking_out_of_range_not_matched(self):
        parsed = parse_args(["+5", "hello"])
        self.assertIsNone(parsed.thinking)
        self.assertEqual(parsed.prompt, "+5 hello")

    def test_tokens_after_prompt_become_part_of_prompt(self):
        parsed = parse_args(["cc", "hello", "+2"])
        self.assertEqual(parsed.runner, "cc")
        self.assertEqual(parsed.prompt, "hello +2")

    def test_multi_word_prompt(self):
        parsed = parse_args(["fix", "the", "bug"])
        self.assertEqual(parsed.prompt, "fix the bug")


class ResolveCommandTests(unittest.TestCase):
    def test_default_runner_is_opencode(self):
        parsed = ParsedArgs(prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[0], "opencode")
        self.assertIn("run", argv)
        self.assertIn("hello", argv)
        self.assertEqual(warnings, [])

    def test_claude_runner(self):
        parsed = ParsedArgs(runner="cc", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["claude", "-p"])
        self.assertNotIn("run", argv)
        self.assertIn("hello", argv)
        self.assertEqual(warnings, [])

    def test_codex_runner_via_c(self):
        parsed = ParsedArgs(runner="c", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["codex", "exec"])
        self.assertEqual(warnings, [])

    def test_codex_runner_via_cx(self):
        parsed = ParsedArgs(runner="cx", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["codex", "exec"])
        self.assertEqual(warnings, [])

    def test_codex_runner_with_model_uses_exec(self):
        parsed = ParsedArgs(runner="c", model="gpt-5.4-mini", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["codex", "exec", "--model", "gpt-5.4-mini", "hello"],
        )
        self.assertEqual(warnings, [])

    def test_thinking_flags_for_claude(self):
        parsed = ParsedArgs(runner="cc", thinking=2, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "medium"],
        )

    def test_plus_three_for_claude_uses_high_flag(self):
        parsed = parse_args(["cc", "+3", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "high"],
        )

    def test_plus_four_for_claude_uses_max_flag(self):
        parsed = parse_args(["cc", "+4", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "max"],
        )

    def test_show_thinking_for_opencode(self):
        parsed = ParsedArgs(show_thinking=True, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["opencode", "run", "--thinking"])

    def test_show_thinking_for_claude(self):
        parsed = ParsedArgs(runner="cc", show_thinking=True, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "low"],
        )

    def test_show_thinking_for_kimi(self):
        parsed = ParsedArgs(runner="k", show_thinking=True, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--thinking"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])

    def test_show_thinking_does_not_override_explicit_thinking(self):
        parsed = ParsedArgs(runner="cc", show_thinking=True, thinking=3, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "high"],
        )

    def test_thinking_zero_for_claude(self):
        parsed = ParsedArgs(runner="cc", thinking=0, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["claude", "-p", "--thinking", "disabled"])
        self.assertNotIn("--effort", argv)

    def test_xhigh_for_claude_uses_max_flag(self):
        parsed = parse_args(["cc", "+xhigh", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "max"],
        )

    def test_max_for_kimi_uses_max_flag(self):
        parsed = parse_args(["k", "+max", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--thinking"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertNotIn("max", argv)
        self.assertNotIn("--think", argv)

    def test_model_flag_for_claude(self):
        parsed = ParsedArgs(runner="cc", model="claude-4", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertIn("--model", argv)
        self.assertIn("claude-4", argv)

    def test_provider_sets_env(self):
        parsed = ParsedArgs(provider="anthropic", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(env.get("CCC_PROVIDER"), "anthropic")

    def test_opencode_sets_terminal_title_env(self):
        parsed = ParsedArgs(runner="oc", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(env.get("OPENCODE_DISABLE_TERMINAL_TITLE"), "true")

    def test_empty_prompt_raises(self):
        parsed = ParsedArgs(prompt="   ")
        with self.assertRaises(ValueError):
            resolve_command(parsed)

    def test_config_default_runner(self):
        config = CccConfig(default_runner="cc")
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(argv[:2], ["claude", "-p"])

    def test_config_default_thinking(self):
        config = CccConfig(default_runner="cc", default_thinking=1)
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "low"],
        )

    def test_config_default_show_thinking(self):
        config = CccConfig(default_runner="cc", default_show_thinking=True)
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "low"],
        )

    def test_config_default_model(self):
        config = CccConfig(default_runner="cc", default_model="claude-3.5")
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertIn("--model", argv)
        self.assertIn("claude-3.5", argv)

    def test_config_abbreviation(self):
        config = CccConfig(abbreviations={"mycc": "cc"})
        parsed = ParsedArgs(runner="mycc", prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(argv[0], "claude")

    def test_alias_provides_defaults(self):
        config = CccConfig(
            aliases={"work": AliasDef(runner="cc", thinking=3, model="claude-4")}
        )
        parsed = ParsedArgs(alias="work", prompt="hello")
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv[:2], ["claude", "-p"])
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "high"],
        )
        self.assertIn("--model", argv)
        self.assertIn("claude-4", argv)
        self.assertEqual(warnings, [])

    def test_alias_prompt_fills_missing_prompt(self):
        config = CccConfig(aliases={"commit": AliasDef(prompt="Commit all changes")})
        parsed = ParsedArgs(alias="commit", prompt="   ")
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv, ["opencode", "run", "Commit all changes"])
        self.assertEqual(warnings, [])

    def test_explicit_prompt_overrides_alias_prompt(self):
        config = CccConfig(aliases={"commit": AliasDef(prompt="Commit all changes")})
        parsed = ParsedArgs(alias="commit", prompt="Write the commit summary")
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv, ["opencode", "run", "Write the commit summary"])
        self.assertEqual(warnings, [])

    def test_explicit_overrides_alias(self):
        config = CccConfig(
            aliases={"work": AliasDef(runner="cc", thinking=3, model="claude-4")}
        )
        parsed = ParsedArgs(runner="k", alias="work", thinking=1, prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(argv[0], "kimi")
        self.assertEqual(argv[:2], ["kimi", "--thinking"])
        self.assertNotIn("--think", argv)

    def test_kimi_thinking_flags(self):
        parsed = ParsedArgs(runner="k", thinking=4, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--thinking"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertNotIn("max", argv)
        self.assertNotIn("--think", argv)

    def test_kimi_thinking_zero_uses_no_thinking(self):
        parsed = ParsedArgs(runner="k", thinking=0, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--no-thinking"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertNotIn("--thinking", argv)

    def test_kimi_uses_prompt_flag(self):
        parsed = ParsedArgs(runner="k", prompt="hello")
        argv, _env, _warnings = resolve_command(parsed)
        self.assertEqual(argv, ["kimi", "--prompt", "hello"])

    def test_alias_falls_back_to_agent_for_opencode(self):
        parsed = ParsedArgs(alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["opencode", "run", "--agent", "reviewer"])
        self.assertEqual(env, {"OPENCODE_DISABLE_TERMINAL_TITLE": "true"})
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_claude(self):
        parsed = ParsedArgs(runner="cc", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["claude", "-p", "--agent", "reviewer"])
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_kimi(self):
        parsed = ParsedArgs(runner="k", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["kimi", "--agent", "reviewer"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_with_warning_when_runner_lacks_support(self):
        parsed = ParsedArgs(runner="rc", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[0], "roocode")
        self.assertNotIn("--agent", argv)
        self.assertEqual(
            warnings,
            ['warning: runner "rc" does not support agents; ignoring @reviewer'],
        )

    def test_alias_preset_can_set_agent(self):
        config = CccConfig(aliases={"work": AliasDef(agent="reviewer")})
        parsed = ParsedArgs(alias="work", prompt="hello")
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv[:4], ["opencode", "run", "--agent", "reviewer"])
        self.assertEqual(warnings, [])

    def test_yolo_for_claude(self):
        parsed = ParsedArgs(runner="cc", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["claude", "-p", "--dangerously-skip-permissions"])
        self.assertEqual(warnings, [])

    def test_yolo_for_codex(self):
        parsed = ParsedArgs(runner="c", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:3],
            ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox"],
        )
        self.assertEqual(warnings, [])

    def test_yolo_for_kimi(self):
        parsed = ParsedArgs(runner="k", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--yolo"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertEqual(warnings, [])

    def test_yolo_for_crush(self):
        parsed = ParsedArgs(runner="cr", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["crush", "run"])
        self.assertEqual(
            warnings,
            ['warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo'],
        )

    def test_yolo_for_opencode_uses_env_override(self):
        parsed = ParsedArgs(runner="oc", yolo=True, prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["opencode", "run", "hello"])
        self.assertEqual(env["OPENCODE_CONFIG_CONTENT"], '{"permission":"allow"}')
        self.assertEqual(warnings, [])

    def test_yolo_for_roocode_warns(self):
        parsed = ParsedArgs(runner="rc", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["roocode", "hello"])
        self.assertEqual(
            warnings,
            ['warning: runner "roocode" yolo mode is unverified; ignoring --yolo'],
        )

    def test_permission_mode_safe_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="safe", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["claude", "-p", "--permission-mode", "default"])
        self.assertEqual(warnings, [])

    def test_permission_mode_auto_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["claude", "-p", "--permission-mode", "auto"])
        self.assertEqual(warnings, [])

    def test_permission_mode_auto_for_codex(self):
        parsed = ParsedArgs(runner="c", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["codex", "exec", "--full-auto"])
        self.assertEqual(warnings, [])

    def test_permission_mode_plan_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="plan", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["claude", "-p", "--permission-mode", "plan"])
        self.assertEqual(warnings, [])

    def test_permission_mode_plan_for_kimi(self):
        parsed = ParsedArgs(runner="k", permission_mode="plan", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["kimi", "--plan"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertEqual(warnings, [])

    def test_permission_mode_auto_warns_for_kimi(self):
        parsed = ParsedArgs(runner="k", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["kimi", "--prompt", "hello"])
        self.assertEqual(
            warnings,
            ['warning: runner "k" does not support permission mode "auto"; ignoring it'],
        )

    def test_invalid_permission_mode_raises(self):
        parsed = ParsedArgs(runner="cc", permission_mode="wild", prompt="hello")
        with self.assertRaises(ValueError):
            resolve_command(parsed)

    def test_output_mode_defaults_to_text(self):
        parsed = ParsedArgs(prompt="hello")
        self.assertEqual(resolve_output_mode(parsed), "text")

    def test_output_mode_uses_alias_default(self):
        config = CccConfig(aliases={"review": AliasDef(output_mode="formatted")})
        parsed = ParsedArgs(alias="review", prompt="hello")
        self.assertEqual(resolve_output_mode(parsed, config), "formatted")

    def test_config_default_output_mode(self):
        config = CccConfig(default_output_mode="stream-formatted")
        parsed = ParsedArgs(prompt="hello")
        self.assertEqual(resolve_output_mode(parsed, config), "stream-formatted")

    def test_sanitize_osc_defaults_on_for_formatted_modes(self):
        parsed = ParsedArgs(output_mode="formatted", prompt="hello")
        self.assertTrue(resolve_sanitize_osc(parsed))

    def test_sanitize_osc_defaults_off_for_raw_modes(self):
        parsed = ParsedArgs(output_mode="json", prompt="hello")
        self.assertFalse(resolve_sanitize_osc(parsed))

    def test_sanitize_osc_uses_alias_default(self):
        config = CccConfig(aliases={"review": AliasDef(sanitize_osc=False)})
        parsed = ParsedArgs(alias="review", output_mode="formatted", prompt="hello")
        self.assertFalse(resolve_sanitize_osc(parsed, config))

    def test_config_default_sanitize_osc(self):
        config = CccConfig(default_sanitize_osc=False)
        parsed = ParsedArgs(output_mode="formatted", prompt="hello")
        self.assertFalse(resolve_sanitize_osc(parsed, config))

    def test_unsupported_output_mode_raises(self):
        parsed = ParsedArgs(runner="oc", output_mode="stream-json", prompt="hello")
        with self.assertRaises(ValueError):
            resolve_output_plan(parsed)

    def test_claude_stream_formatted_output_plan(self):
        parsed = ParsedArgs(runner="cc", output_mode="stream-formatted", prompt="hello")
        plan = resolve_output_plan(parsed)
        self.assertTrue(plan.stream)
        self.assertTrue(plan.formatted)
        self.assertEqual(plan.schema, "claude-code")
        self.assertEqual(
            plan.argv_flags,
            ["--verbose", "--output-format", "stream-json", "--include-partial-messages"],
        )

    def test_kimi_stream_json_output_plan(self):
        parsed = ParsedArgs(runner="k", output_mode="stream-json", prompt="hello")
        plan = resolve_output_plan(parsed)
        self.assertTrue(plan.stream)
        self.assertFalse(plan.formatted)
        self.assertEqual(plan.schema, "kimi")
        self.assertEqual(plan.argv_flags, ["--print", "--output-format", "stream-json"])

    def test_opencode_json_output_plan(self):
        parsed = ParsedArgs(runner="oc", output_mode="json", prompt="hello")
        plan = resolve_output_plan(parsed)
        self.assertEqual(plan.schema, "opencode")
        self.assertEqual(plan.argv_flags, ["--format", "json"])

    def test_show_thinking_resolution_uses_alias(self):
        config = CccConfig(aliases={"review": AliasDef(show_thinking=True)})
        parsed = ParsedArgs(alias="review", prompt="hello")
        self.assertTrue(resolve_show_thinking(parsed, config))


class LoadConfigTests(unittest.TestCase):
    def test_missing_file_returns_defaults(self):
        config = load_config("/nonexistent/path/config.toml")
        self.assertEqual(config.default_runner, "oc")
        self.assertEqual(config.aliases, {})

    def test_valid_toml_config(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"""
[defaults]
runner = "cc"
provider = "anthropic"
model = "claude-4"
output_mode = "stream-formatted"
thinking = 2
show_thinking = true
sanitize_osc = false

[abbreviations]
mycc = "cc"

[aliases.work]
runner = "cc"
thinking = 3
show_thinking = true
sanitize_osc = false
output_mode = "formatted"
model = "claude-4"
agent = "reviewer"

[aliases.quick]
runner = "oc"

[aliases.commit]
prompt = "Commit all changes"
""")
            f.flush()
            config = load_config(f.name)

        self.assertEqual(config.default_runner, "cc")
        self.assertEqual(config.default_provider, "anthropic")
        self.assertEqual(config.default_model, "claude-4")
        self.assertEqual(config.default_output_mode, "stream-formatted")
        self.assertEqual(config.default_thinking, 2)
        self.assertTrue(config.default_show_thinking)
        self.assertFalse(config.default_sanitize_osc)
        self.assertEqual(config.abbreviations, {"mycc": "cc"})
        self.assertIn("work", config.aliases)
        self.assertEqual(config.aliases["work"].runner, "cc")
        self.assertEqual(config.aliases["work"].thinking, 3)
        self.assertEqual(config.aliases["work"].model, "claude-4")
        self.assertEqual(config.aliases["work"].agent, "reviewer")
        self.assertTrue(config.aliases["work"].show_thinking)
        self.assertFalse(config.aliases["work"].sanitize_osc)
        self.assertEqual(config.aliases["work"].output_mode, "formatted")
        self.assertIn("quick", config.aliases)
        self.assertEqual(config.aliases["quick"].runner, "oc")
        self.assertEqual(config.aliases["commit"].prompt, "Commit all changes")

    def test_legacy_default_output_mode(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b'default_output_mode = "json"\n')
            f.flush()
            config = load_config(f.name)
        self.assertEqual(config.default_output_mode, "json")

    def test_legacy_default_sanitize_osc(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"default_sanitize_osc = false\n")
            f.flush()
            config = load_config(f.name)
        self.assertFalse(config.default_sanitize_osc)

    def test_project_local_config_layers_over_global_configs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home_root = tmp_path / "home"
            xdg_root = tmp_path / "xdg"
            workspace_root = tmp_path / "workspace"
            repo_root = workspace_root / "repo"
            nested_cwd = repo_root / "nested" / "deeper"
            nested_cwd.mkdir(parents=True)

            (workspace_root / ".ccc.toml").write_text(
                '[defaults]\nrunner = "oc"\n[aliases.review]\nagent = "outer-agent"\n'
            )
            (repo_root / ".ccc.toml").write_text(
                '[aliases.review]\nprompt = "Repo prompt"\n'
            )

            home_config_dir = home_root / ".config" / "ccc"
            xdg_config_dir = xdg_root / "ccc"
            home_config_dir.mkdir(parents=True)
            xdg_config_dir.mkdir(parents=True)
            (home_config_dir / "config.toml").write_text(
                '[defaults]\nrunner = "k"\n[aliases.review]\nshow_thinking = true\n'
            )
            (xdg_config_dir / "config.toml").write_text(
                '[defaults]\nmodel = "xdg-model"\n[aliases.review]\nmodel = "xdg-model"\n'
            )

            old_cwd = Path.cwd()
            try:
                os.chdir(nested_cwd)
                with mock.patch.dict(
                    os.environ,
                    {"HOME": str(home_root), "XDG_CONFIG_HOME": str(xdg_root)},
                    clear=False,
                ):
                    config = load_config()
            finally:
                os.chdir(old_cwd)

            self.assertEqual(config.default_runner, "k")
            self.assertEqual(config.default_model, "xdg-model")
            self.assertIn("review", config.aliases)
            self.assertEqual(config.aliases["review"].prompt, "Repo prompt")
            self.assertEqual(config.aliases["review"].model, "xdg-model")
            self.assertTrue(config.aliases["review"].show_thinking)
            self.assertIsNone(config.aliases["review"].agent)

    def test_empty_toml_returns_defaults(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"")
            f.flush()
            config = load_config(f.name)
        self.assertEqual(config.default_runner, "oc")


class RegistryTests(unittest.TestCase):
    def test_all_selectors_registered(self):
        for sel in [
            "oc",
            "cc",
            "c",
            "cx",
            "k",
            "rc",
            "cr",
            "codex",
            "claude",
            "opencode",
            "kimi",
            "roocode",
            "crush",
        ]:
            self.assertIn(sel, RUNNER_REGISTRY, f"Missing selector: {sel}")

    def test_abbreviations_point_to_same_info(self):
        self.assertIs(RUNNER_REGISTRY["oc"], RUNNER_REGISTRY["opencode"])
        self.assertIs(RUNNER_REGISTRY["cc"], RUNNER_REGISTRY["claude"])
        self.assertIs(RUNNER_REGISTRY["c"], RUNNER_REGISTRY["codex"])
        self.assertIs(RUNNER_REGISTRY["cx"], RUNNER_REGISTRY["codex"])
        self.assertIs(RUNNER_REGISTRY["k"], RUNNER_REGISTRY["kimi"])
        self.assertIs(RUNNER_REGISTRY["rc"], RUNNER_REGISTRY["roocode"])


if __name__ == "__main__":
    unittest.main()

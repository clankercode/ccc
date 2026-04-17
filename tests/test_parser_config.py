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
from call_coding_clis.config import (
    find_alias_write_path,
    find_config_command_path,
    load_config,
    render_example_config,
    render_alias_block,
    upsert_alias_block,
)


FIXTURE_CONFIG_PATH = Path(__file__).parent / "fixtures" / "config-example.toml"


def read_example_config_fixture() -> str:
    return FIXTURE_CONFIG_PATH.read_text(encoding="utf-8")


class ParseArgsTests(unittest.TestCase):
    def test_prompt_only(self):
        parsed = parse_args(["hello world"])
        self.assertEqual(parsed.prompt, "hello world")
        self.assertTrue(parsed.prompt_supplied)
        self.assertIsNone(parsed.runner)
        self.assertIsNone(parsed.thinking)
        self.assertIsNone(parsed.show_thinking)
        self.assertIsNone(parsed.sanitize_osc)
        self.assertFalse(parsed.yolo)
        self.assertIsNone(parsed.permission_mode)
        self.assertIsNone(parsed.provider)
        self.assertIsNone(parsed.model)
        self.assertIsNone(parsed.alias)
        self.assertFalse(parsed.print_config)

    def test_print_config_flag(self):
        parsed = parse_args(["--print-config"])
        self.assertTrue(parsed.print_config)
        self.assertEqual(parsed.prompt, "")
        self.assertFalse(parsed.prompt_supplied)

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

    def test_unregistered_pi_is_prompt_text(self):
        parsed = parse_args(["pi", "hello"])
        self.assertIsNone(parsed.runner)
        self.assertEqual(parsed.prompt, "pi hello")

    def test_runner_selector_cursor_and_cu(self):
        for selector in ("cursor", "cu"):
            with self.subTest(selector=selector):
                parsed = parse_args([selector, "hello"])
                self.assertEqual(parsed.runner, selector)
                self.assertEqual(parsed.prompt, "hello")

    def test_runner_selector_gemini_and_g(self):
        for selector in ("gemini", "g"):
            with self.subTest(selector=selector):
                parsed = parse_args([selector, "hello"])
                self.assertEqual(parsed.runner, selector)
                self.assertEqual(parsed.prompt, "hello")

    def test_runner_selector_cr_remains_crush(self):
        parsed = parse_args(["cr", "hello"])
        self.assertEqual(parsed.runner, "cr")
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

    def test_save_session_flag(self):
        parsed = parse_args(["--save-session", "hello"])
        self.assertTrue(parsed.save_session)
        self.assertFalse(parsed.cleanup_session)
        self.assertEqual(parsed.prompt, "hello")

    def test_cleanup_session_flag(self):
        parsed = parse_args(["--cleanup-session", "hello"])
        self.assertTrue(parsed.cleanup_session)
        self.assertFalse(parsed.save_session)
        self.assertEqual(parsed.prompt, "hello")

    def test_timeout_secs_flag_parses_positive_integer(self):
        parsed = parse_args(["--timeout-secs", "30", "hello"])
        self.assertEqual(parsed.timeout_secs, 30)
        self.assertEqual(parsed.prompt, "hello")

    def test_timeout_secs_rejects_non_integer(self):
        with self.assertRaises(ValueError) as cm:
            parse_args(["--timeout-secs", "abc", "hello"])
        self.assertEqual(
            str(cm.exception), "--timeout-secs must be a positive integer"
        )

    def test_timeout_secs_rejects_zero(self):
        with self.assertRaises(ValueError) as cm:
            parse_args(["--timeout-secs", "0", "hello"])
        self.assertEqual(
            str(cm.exception), "--timeout-secs must be a positive integer"
        )

    def test_timeout_secs_rejects_negative(self):
        with self.assertRaises(ValueError) as cm:
            parse_args(["--timeout-secs", "-5", "hello"])
        self.assertEqual(
            str(cm.exception), "--timeout-secs must be a positive integer"
        )

    def test_timeout_secs_rejects_missing_value(self):
        with self.assertRaises(ValueError) as cm:
            parse_args(["--timeout-secs"])
        self.assertEqual(
            str(cm.exception), "--timeout-secs must be a positive integer"
        )

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

    def test_double_dash_treats_print_config_as_prompt_text(self):
        parsed = parse_args(["--", "--print-config"])
        self.assertFalse(parsed.print_config)
        self.assertEqual(parsed.prompt, "--print-config")
        self.assertTrue(parsed.prompt_supplied)

    def test_empty_string_prompt_counts_as_supplied(self):
        parsed = parse_args([""])
        self.assertEqual(parsed.prompt, "")
        self.assertTrue(parsed.prompt_supplied)

    def test_whitespace_prompt_counts_as_supplied(self):
        parsed = parse_args(["   "])
        self.assertEqual(parsed.prompt, "   ")
        self.assertTrue(parsed.prompt_supplied)

    def test_permission_mode_missing_value_errors_in_resolve(self):
        parsed = parse_args(["--permission-mode"])
        self.assertEqual(parsed.permission_mode, "")
        with self.assertRaises(ValueError):
            resolve_command(parsed)

    def test_save_session_and_cleanup_session_conflict(self):
        parsed = parse_args(["--save-session", "--cleanup-session", "hello"])
        with self.assertRaisesRegex(ValueError, "mutually exclusive"):
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
        self.assertIn("--no-session-persistence", argv)
        self.assertNotIn("run", argv)
        self.assertIn("hello", argv)
        self.assertEqual(warnings, [])

    def test_codex_runner_via_c(self):
        parsed = ParsedArgs(runner="c", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["codex", "exec"])
        self.assertIn("--ephemeral", argv)
        self.assertEqual(warnings, [])

    def test_codex_runner_via_cx(self):
        parsed = ParsedArgs(runner="cx", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["codex", "exec"])
        self.assertIn("--ephemeral", argv)
        self.assertEqual(warnings, [])

    def test_cursor_runner_via_cu(self):
        parsed = ParsedArgs(runner="cu", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["cursor-agent", "--print", "--trust", "hello"])
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_cursor_runner_long_name_with_model(self):
        parsed = ParsedArgs(runner="cursor", model="gpt-5", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["cursor-agent", "--print", "--trust", "--model", "gpt-5", "hello"],
        )
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_gemini_runner_via_g_uses_prompt_flag(self):
        parsed = ParsedArgs(runner="g", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["gemini", "--prompt", "hello"])
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_gemini_runner_long_name_with_model(self):
        parsed = ParsedArgs(runner="gemini", model="gemini-2.5-pro", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["gemini", "--model", "gemini-2.5-pro", "--prompt", "hello"],
        )
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_cr_still_resolves_to_crush(self):
        parsed = ParsedArgs(runner="cr", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["crush", "run", "hello"])
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_codex_runner_with_model_uses_exec(self):
        parsed = ParsedArgs(runner="c", model="gpt-5.4-mini", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["codex", "exec", "--model", "gpt-5.4-mini", "--ephemeral", "hello"],
        )
        self.assertEqual(warnings, [])

    def test_save_session_preserves_old_claude_and_codex_argv(self):
        cases = [
            (
                ParsedArgs(runner="cc", save_session=True, prompt="hello"),
                ["claude", "-p", "--thinking", "enabled", "--effort", "low", "hello"],
            ),
            (ParsedArgs(runner="c", save_session=True, prompt="hello"), ["codex", "exec", "hello"]),
        ]
        for parsed, expected in cases:
            with self.subTest(runner=parsed.runner):
                argv, _env, warnings = resolve_command(parsed)
                self.assertEqual(argv, expected)
                self.assertEqual(warnings, [])

    def test_resolve_command_does_not_emit_default_persistence_warnings(self):
        cases = [
            "oc",
            "k",
            "cr",
            "rc",
        ]
        for runner in cases:
            with self.subTest(runner=runner):
                _argv, _env, warnings = resolve_command(ParsedArgs(runner=runner, prompt="hello"))
                self.assertNotIn("may save this session", "\n".join(warnings))

    def test_cleanup_session_suppresses_persistence_warning_for_supported_cleanup_runners(self):
        for runner in ("oc", "k"):
            with self.subTest(runner=runner):
                _argv, _env, warnings = resolve_command(
                    ParsedArgs(runner=runner, cleanup_session=True, prompt="hello")
                )
                self.assertNotIn("may save this session", "\n".join(warnings))

    def test_cleanup_session_warns_for_unsupported_cleanup_runners(self):
        for runner, display in (
            ("cr", "crush"),
            ("rc", "roocode"),
            ("cu", "cursor"),
            ("g", "gemini"),
        ):
            with self.subTest(runner=runner):
                _argv, _env, warnings = resolve_command(
                    ParsedArgs(runner=runner, cleanup_session=True, prompt="hello")
                )
                self.assertIn(
                    f'warning: runner "{display}" does not support automatic session cleanup; pass --save-session to allow saved sessions explicitly',
                    warnings,
                )

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

    def test_default_show_thinking_enables_opencode_thinking(self):
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["opencode", "run", "--thinking"])

    def test_default_thinking_effort_is_low_for_claude(self):
        parsed = ParsedArgs(runner="cc", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:6],
            ["claude", "-p", "--thinking", "enabled", "--effort", "low"],
        )

    def test_no_show_thinking_overrides_default_for_opencode(self):
        parsed = ParsedArgs(show_thinking=False, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(argv[:2], ["opencode", "run"])
        self.assertNotIn("--thinking", argv)

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
        self.assertEqual(argv, ["opencode", "run", "--thinking", "Commit all changes"])
        self.assertEqual(warnings, [])

    def test_explicit_prompt_overrides_alias_prompt(self):
        config = CccConfig(aliases={"commit": AliasDef(prompt="Commit all changes")})
        parsed = ParsedArgs(alias="commit", prompt="Write the commit summary")
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv, ["opencode", "run", "--thinking", "Write the commit summary"])
        self.assertEqual(warnings, [])

    def test_alias_prompt_mode_prepend_uses_newline_separator(self):
        config = CccConfig(
            aliases={
                "commit": AliasDef(
                    prompt="Commit all changes",
                    prompt_mode="prepend",
                )
            }
        )
        parsed = ParsedArgs(
            alias="commit",
            prompt="Include the failing tests",
            prompt_supplied=True,
        )
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(
            argv,
            [
                "opencode",
                "run",
                "--thinking",
                "Commit all changes\nInclude the failing tests",
            ],
        )
        self.assertEqual(warnings, [])

    def test_alias_prompt_mode_append_uses_newline_separator(self):
        config = CccConfig(
            aliases={
                "commit": AliasDef(
                    prompt="Commit all changes",
                    prompt_mode="append",
                )
            }
        )
        parsed = ParsedArgs(
            alias="commit",
            prompt="Include the failing tests",
            prompt_supplied=True,
        )
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(
            argv,
            [
                "opencode",
                "run",
                "--thinking",
                "Include the failing tests\nCommit all changes",
            ],
        )
        self.assertEqual(warnings, [])

    def test_alias_prompt_mode_requires_supplied_prompt(self):
        config = CccConfig(
            aliases={
                "commit": AliasDef(
                    prompt="Commit all changes",
                    prompt_mode="append",
                )
            }
        )
        parsed = ParsedArgs(alias="commit", prompt="")
        with self.assertRaisesRegex(
            ValueError,
            "prompt_mode append requires an explicit prompt argument",
        ):
            resolve_command(parsed, config)

    def test_alias_prompt_mode_allows_explicit_empty_prompt(self):
        config = CccConfig(
            aliases={
                "commit": AliasDef(
                    prompt="Commit all changes",
                    prompt_mode="prepend",
                )
            }
        )
        parsed = ParsedArgs(alias="commit", prompt="", prompt_supplied=True)
        argv, env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv, ["opencode", "run", "--thinking", "Commit all changes"])
        self.assertEqual(warnings, [])

    def test_alias_prompt_mode_requires_non_empty_alias_prompt(self):
        config = CccConfig(
            aliases={"commit": AliasDef(prompt="   ", prompt_mode="append")}
        )
        parsed = ParsedArgs(alias="commit", prompt="Add tests", prompt_supplied=True)
        with self.assertRaisesRegex(
            ValueError,
            "prompt_mode append requires aliases.commit.prompt",
        ):
            resolve_command(parsed, config)

    def test_alias_prompt_mode_rejects_invalid_value(self):
        config = CccConfig(
            aliases={"commit": AliasDef(prompt="Commit all changes", prompt_mode="replace")}
        )
        parsed = ParsedArgs(alias="commit", prompt="Add tests", prompt_supplied=True)
        with self.assertRaisesRegex(
            ValueError,
            "prompt_mode must be one of: default, prepend, append",
        ):
            resolve_command(parsed, config)

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
        self.assertEqual(argv, ["kimi", "--thinking", "--prompt", "hello"])

    def test_alias_falls_back_to_agent_for_opencode(self):
        parsed = ParsedArgs(alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:5], ["opencode", "run", "--thinking", "--agent", "reviewer"])
        self.assertEqual(env, {"OPENCODE_DISABLE_TERMINAL_TITLE": "true"})
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_claude(self):
        parsed = ParsedArgs(runner="cc", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:8],
            [
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "--agent",
                "reviewer",
            ],
        )
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_kimi(self):
        parsed = ParsedArgs(runner="k", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["kimi", "--thinking", "--agent", "reviewer"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertEqual(warnings, [])

    def test_unresolved_alias_matching_runner_selector_selects_runner(self):
        config = CccConfig(default_runner="k", default_output_mode="stream-formatted")
        parsed = ParsedArgs(alias="k", prompt="hello")
        argv, _env, warnings = resolve_command(parsed, config)
        self.assertEqual(
            argv,
            ["kimi", "--print", "--output-format", "stream-json", "--thinking", "--prompt", "hello"],
        )
        self.assertNotIn("--agent", argv)
        self.assertEqual(warnings, [])

    def test_explicit_runner_keeps_runner_like_alias_as_agent(self):
        parsed = parse_args(["oc", "@k", "hello"])
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["opencode", "run", "--thinking", "--agent", "k", "hello"],
        )
        self.assertEqual(warnings, [])

    def test_configured_alias_named_like_runner_selector_wins(self):
        config = CccConfig(
            aliases={"k": AliasDef(runner="oc", agent="specialist")}
        )
        parsed = ParsedArgs(alias="k", prompt="hello")
        argv, _env, warnings = resolve_command(parsed, config)
        self.assertEqual(argv[:5], ["opencode", "run", "--thinking", "--agent", "specialist"])
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
        self.assertEqual(argv[:5], ["opencode", "run", "--thinking", "--agent", "reviewer"])
        self.assertEqual(warnings, [])

    def test_yolo_for_claude(self):
        parsed = ParsedArgs(runner="cc", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:7],
            [
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "--dangerously-skip-permissions",
            ],
        )
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
        self.assertEqual(argv[:3], ["kimi", "--thinking", "--yolo"])
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
        self.assertEqual(argv, ["opencode", "run", "--thinking", "hello"])
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

    def test_yolo_for_cursor(self):
        parsed = ParsedArgs(runner="cu", yolo=True, prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv,
            ["cursor-agent", "--print", "--trust", "--yolo", "hello"],
        )
        self.assertEqual(warnings, [])

    def test_permission_mode_safe_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="safe", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:8],
            [
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "--permission-mode",
                "default",
            ],
        )
        self.assertEqual(warnings, [])

    def test_permission_mode_safe_for_opencode_uses_ask_override(self):
        parsed = ParsedArgs(runner="oc", permission_mode="safe", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["opencode", "run", "--thinking", "hello"])
        self.assertEqual(env["OPENCODE_CONFIG_CONTENT"], '{"permission":"ask"}')
        self.assertEqual(warnings, [])

    def test_permission_mode_safe_for_roocode_warns(self):
        parsed = ParsedArgs(runner="rc", permission_mode="safe", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["roocode", "hello"])
        self.assertEqual(
            warnings,
            ['warning: runner "roocode" safe mode is unverified; leaving default permissions unchanged'],
        )

    def test_permission_modes_for_cursor(self):
        cases = [
            (
                "safe",
                ["cursor-agent", "--print", "--trust", "--sandbox", "enabled", "hello"],
                [],
            ),
            (
                "plan",
                ["cursor-agent", "--print", "--trust", "--mode", "plan", "hello"],
                [],
            ),
            (
                "auto",
                ["cursor-agent", "--print", "--trust", "hello"],
                [
                    'warning: runner "cu" does not support permission mode "auto"; ignoring it'
                ],
            ),
        ]
        for mode, expected_argv, expected_warnings in cases:
            with self.subTest(mode=mode):
                parsed = ParsedArgs(runner="cu", permission_mode=mode, prompt="hello")
                argv, _env, warnings = resolve_command(parsed)
                self.assertEqual(argv, expected_argv)
                self.assertEqual(warnings, expected_warnings)

    def test_permission_modes_for_gemini(self):
        cases = [
            (
                "safe",
                ["gemini", "--approval-mode", "default", "--sandbox", "--prompt", "hello"],
            ),
            (
                "auto",
                ["gemini", "--approval-mode", "auto_edit", "--prompt", "hello"],
            ),
            (
                "yolo",
                ["gemini", "--approval-mode", "yolo", "--prompt", "hello"],
            ),
            (
                "plan",
                ["gemini", "--approval-mode", "plan", "--prompt", "hello"],
            ),
        ]
        for mode, expected_argv in cases:
            with self.subTest(mode=mode):
                parsed = ParsedArgs(runner="g", permission_mode=mode, prompt="hello")
                argv, env, warnings = resolve_command(parsed)
                self.assertEqual(argv, expected_argv)
                self.assertEqual(env, {})
                self.assertEqual(warnings, [])

    def test_permission_mode_auto_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:8],
            [
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "--permission-mode",
                "auto",
            ],
        )
        self.assertEqual(warnings, [])

    def test_permission_mode_auto_for_codex(self):
        parsed = ParsedArgs(runner="c", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["codex", "exec", "--full-auto"])
        self.assertEqual(warnings, [])

    def test_permission_mode_plan_for_claude(self):
        parsed = ParsedArgs(runner="cc", permission_mode="plan", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(
            argv[:8],
            [
                "claude",
                "-p",
                "--thinking",
                "enabled",
                "--effort",
                "low",
                "--permission-mode",
                "plan",
            ],
        )
        self.assertEqual(warnings, [])

    def test_permission_mode_plan_for_kimi(self):
        parsed = ParsedArgs(runner="k", permission_mode="plan", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["kimi", "--thinking", "--plan"])
        self.assertEqual(argv[-2:], ["--prompt", "hello"])
        self.assertEqual(warnings, [])

    def test_permission_mode_auto_warns_for_kimi(self):
        parsed = ParsedArgs(runner="k", permission_mode="auto", prompt="hello")
        argv, _env, warnings = resolve_command(parsed)
        self.assertEqual(argv, ["kimi", "--thinking", "--prompt", "hello"])
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

    def test_sanitize_osc_defaults_off_after_output_mode_fallback(self):
        config = CccConfig(default_output_mode="stream-formatted")
        parsed = ParsedArgs(runner="rc", prompt="hello")
        self.assertFalse(resolve_sanitize_osc(parsed, config))

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

    def test_opencode_stream_json_output_plan(self):
        parsed = ParsedArgs(runner="oc", output_mode="stream-json", prompt="hello")
        plan = resolve_output_plan(parsed)
        self.assertTrue(plan.stream)
        self.assertFalse(plan.formatted)
        self.assertEqual(plan.schema, "opencode")
        self.assertEqual(plan.argv_flags, ["--format", "json"])

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

    def test_opencode_stream_formatted_output_plan(self):
        parsed = ParsedArgs(runner="oc", output_mode="stream-formatted", prompt="hello")
        plan = resolve_output_plan(parsed)
        self.assertTrue(plan.stream)
        self.assertTrue(plan.formatted)
        self.assertEqual(plan.schema, "opencode")
        self.assertEqual(plan.argv_flags, ["--format", "json"])

    def test_codex_output_plans(self):
        cases = [
            ("json", False, False),
            ("stream-json", True, False),
            ("formatted", False, True),
            ("stream-formatted", True, True),
        ]
        for mode, stream, formatted in cases:
            with self.subTest(mode=mode):
                parsed = ParsedArgs(runner="c", output_mode=mode, prompt="hello")
                plan = resolve_output_plan(parsed)
                self.assertEqual(plan.stream, stream)
                self.assertEqual(plan.formatted, formatted)
                self.assertEqual(plan.schema, "codex")
                self.assertEqual(plan.argv_flags, ["--json"])

    def test_cursor_output_plans(self):
        cases = [
            ("json", False, False, ["--output-format", "json"]),
            ("stream-json", True, False, ["--output-format", "stream-json"]),
            ("formatted", False, True, ["--output-format", "stream-json"]),
            ("stream-formatted", True, True, ["--output-format", "stream-json"]),
        ]
        for mode, stream, formatted, flags in cases:
            with self.subTest(mode=mode):
                parsed = ParsedArgs(runner="cu", output_mode=mode, prompt="hello")
                plan = resolve_output_plan(parsed)
                self.assertEqual(plan.stream, stream)
                self.assertEqual(plan.formatted, formatted)
                self.assertEqual(plan.schema, "cursor-agent")
                self.assertEqual(plan.argv_flags, flags)

    def test_gemini_output_plans(self):
        cases = [
            ("json", False, False, ["--output-format", "json"]),
            ("stream-json", True, False, ["--output-format", "stream-json"]),
            ("formatted", False, True, ["--output-format", "stream-json"]),
            ("stream-formatted", True, True, ["--output-format", "stream-json"]),
        ]
        for mode, stream, formatted, flags in cases:
            with self.subTest(mode=mode):
                parsed = ParsedArgs(runner="g", output_mode=mode, prompt="hello")
                plan = resolve_output_plan(parsed)
                self.assertEqual(plan.stream, stream)
                self.assertEqual(plan.formatted, formatted)
                self.assertEqual(plan.schema, "gemini")
                self.assertEqual(plan.argv_flags, flags)

    def test_configured_unsupported_output_mode_falls_back_to_text(self):
        config = CccConfig(default_output_mode="stream-formatted")
        parsed = ParsedArgs(runner="rc", prompt="hello")
        plan = resolve_output_plan(parsed, config)
        self.assertEqual(plan.mode, "text")
        self.assertEqual(plan.argv_flags, [])
        self.assertEqual(
            plan.warnings,
            [
                'warning: runner "roocode" does not support configured output mode "stream-formatted"; falling back to "text"'
            ],
        )

    def test_alias_unsupported_output_mode_falls_back_to_text(self):
        config = CccConfig(
            aliases={"fast": AliasDef(runner="rc", output_mode="stream-formatted")}
        )
        parsed = ParsedArgs(alias="fast", prompt="hello")
        plan = resolve_output_plan(parsed, config)
        self.assertEqual(plan.runner_name, "rc")
        self.assertEqual(plan.mode, "text")
        self.assertEqual(
            plan.warnings,
            [
                'warning: runner "roocode" does not support alias output mode "stream-formatted"; falling back to "text"'
            ],
        )

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
prompt_mode = "append"
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
        self.assertEqual(config.aliases["commit"].prompt_mode, "append")

    def test_render_example_config_matches_fixture(self):
        self.assertEqual(render_example_config(), read_example_config_fixture())

    def test_legacy_default_output_mode_is_ignored(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b'default_output_mode = "json"\n')
            f.flush()
            config = load_config(f.name)
        self.assertEqual(config.default_output_mode, "text")

    def test_legacy_default_show_thinking_is_ignored(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"default_show_thinking = true\n")
            f.flush()
            config = load_config(f.name)
        self.assertTrue(config.default_show_thinking)

    def test_legacy_default_sanitize_osc_is_ignored(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"default_sanitize_osc = false\n")
            f.flush()
            config = load_config(f.name)
        self.assertIsNone(config.default_sanitize_osc)

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

    def test_project_local_config_merges_abbreviations_by_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home_root = tmp_path / "home"
            xdg_root = tmp_path / "xdg"
            repo_root = tmp_path / "repo"
            nested_cwd = repo_root / "nested"
            nested_cwd.mkdir(parents=True)

            (repo_root / ".ccc.toml").write_text('[abbreviations]\nteam = "k"\n')

            home_config_dir = home_root / ".config" / "ccc"
            xdg_config_dir = xdg_root / "ccc"
            home_config_dir.mkdir(parents=True)
            xdg_config_dir.mkdir(parents=True)
            (home_config_dir / "config.toml").write_text('[abbreviations]\nlegacy = "cc"\n')
            (xdg_config_dir / "config.toml").write_text('[abbreviations]\nmodern = "oc"\n')

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

            self.assertEqual(
                config.abbreviations,
                {"legacy": "cc", "modern": "oc", "team": "k"},
            )

    def test_explicit_config_path_ignores_ambient_project_local_and_global_configs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home_root = tmp_path / "home"
            xdg_root = tmp_path / "xdg"
            repo_root = tmp_path / "repo"
            nested_cwd = repo_root / "nested"
            nested_cwd.mkdir(parents=True)

            explicit_config = tmp_path / "explicit.toml"
            explicit_config.write_text('[defaults]\nrunner = "cc"\n')
            (repo_root / ".ccc.toml").write_text('[defaults]\nrunner = "k"\n')

            home_config_dir = home_root / ".config" / "ccc"
            xdg_config_dir = xdg_root / "ccc"
            home_config_dir.mkdir(parents=True)
            xdg_config_dir.mkdir(parents=True)
            (home_config_dir / "config.toml").write_text('[defaults]\nrunner = "oc"\n')
            (xdg_config_dir / "config.toml").write_text('[defaults]\nrunner = "c"\n')

            old_cwd = Path.cwd()
            try:
                os.chdir(nested_cwd)
                with mock.patch.dict(
                    os.environ,
                    {"HOME": str(home_root), "XDG_CONFIG_HOME": str(xdg_root)},
                    clear=False,
                ):
                    config = load_config(explicit_config)
            finally:
                os.chdir(old_cwd)

            self.assertEqual(config.default_runner, "cc")
            self.assertEqual(config.aliases, {})
            self.assertEqual(config.abbreviations, {})

    def test_find_config_command_path_prefers_explicit_ccc_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            explicit_path = tmp_path / "explicit.toml"
            explicit_path.write_text('[defaults]\nrunner = "cc"\n')
            with mock.patch.dict(os.environ, {"CCC_CONFIG": str(explicit_path)}, clear=False):
                self.assertEqual(find_config_command_path(), explicit_path)

    def test_find_config_command_path_prefers_project_local_then_xdg_then_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home_root = tmp_path / "home"
            xdg_root = tmp_path / "xdg"
            repo_root = tmp_path / "repo"
            nested_cwd = repo_root / "nested"
            nested_cwd.mkdir(parents=True)

            project_path = repo_root / ".ccc.toml"
            xdg_path = xdg_root / "ccc" / "config.toml"
            home_path = home_root / ".config" / "ccc" / "config.toml"
            project_path.write_text('[defaults]\nrunner = "cc"\n')
            xdg_path.parent.mkdir(parents=True)
            xdg_path.write_text('[defaults]\nrunner = "k"\n')
            home_path.parent.mkdir(parents=True)
            home_path.write_text('[defaults]\nrunner = "oc"\n')

            old_cwd = Path.cwd()
            try:
                os.chdir(nested_cwd)
                with mock.patch.dict(
                    os.environ,
                    {
                        "HOME": str(home_root),
                        "XDG_CONFIG_HOME": str(xdg_root),
                        "CCC_CONFIG": "",
                    },
                    clear=False,
                ):
                    self.assertEqual(find_config_command_path(), project_path)
            finally:
                os.chdir(old_cwd)

    def test_find_config_command_path_falls_back_when_ccc_config_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            home_root = tmp_path / "home"
            xdg_root = tmp_path / "xdg"
            xdg_path = xdg_root / "ccc" / "config.toml"
            xdg_path.parent.mkdir(parents=True)
            xdg_path.write_text('[defaults]\nrunner = "k"\n')
            missing_path = tmp_path / "missing.toml"

            with mock.patch.dict(
                os.environ,
                {
                    "HOME": str(home_root),
                    "XDG_CONFIG_HOME": str(xdg_root),
                    "CCC_CONFIG": str(missing_path),
                },
                clear=False,
            ):
                self.assertEqual(find_config_command_path(), xdg_path)

    def test_empty_toml_returns_defaults(self):
        with tempfile.NamedTemporaryFile(mode="wb", suffix=".toml", delete=False) as f:
            f.write(b"")
            f.flush()
            config = load_config(f.name)
        self.assertEqual(config.default_runner, "oc")

    def test_render_alias_block_omits_unset_keys_and_escapes_strings(self):
        alias = AliasDef(
            runner="cc",
            model='claude "quoted"',
            thinking=3,
            show_thinking=True,
            prompt="Review\nchanges",
            prompt_mode="append",
        )

        self.assertEqual(
            render_alias_block("mm27", alias),
            '[aliases.mm27]\n'
            'runner = "cc"\n'
            'model = "claude \\"quoted\\""\n'
            'thinking = 3\n'
            'show_thinking = true\n'
            'prompt = "Review\\nchanges"\n'
            'prompt_mode = "append"\n',
        )

    def test_upsert_alias_block_replaces_only_target_alias(self):
        content = (
            "# keep me\n"
            "[defaults]\n"
            'runner = "oc"\n'
            "\n"
            "[aliases.mm27]\n"
            'runner = "cc"\n'
            'prompt = "old"\n'
            "\n"
            "[aliases.other]\n"
            'prompt = "keep"\n'
        )
        alias = AliasDef(runner="k", prompt="new")

        updated = upsert_alias_block(content, "mm27", alias)

        self.assertEqual(
            updated,
            "# keep me\n"
            "[defaults]\n"
            'runner = "oc"\n'
            "\n"
            "[aliases.mm27]\n"
            'runner = "k"\n'
            'prompt = "new"\n'
            "\n"
            "[aliases.other]\n"
            'prompt = "keep"\n',
        )

    def test_find_alias_write_path_defaults_to_new_xdg_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            with mock.patch.dict(
                os.environ,
                {
                    "HOME": str(tmp_path / "home"),
                    "XDG_CONFIG_HOME": str(tmp_path / "xdg"),
                    "CCC_CONFIG": str(tmp_path / "missing.toml"),
                },
                clear=False,
            ):
                self.assertEqual(
                    find_alias_write_path(global_only=False),
                    tmp_path / "xdg" / "ccc" / "config.toml",
                )

    def test_find_alias_write_path_global_ignores_project_and_prefers_xdg(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_root = tmp_path / "repo"
            nested = repo_root / "nested"
            nested.mkdir(parents=True)
            project_config = repo_root / ".ccc.toml"
            project_config.write_text("[aliases.local]\n", encoding="utf-8")
            home_config = tmp_path / "home" / ".config" / "ccc" / "config.toml"
            xdg_config = tmp_path / "xdg" / "ccc" / "config.toml"
            home_config.parent.mkdir(parents=True)
            xdg_config.parent.mkdir(parents=True)
            home_config.write_text("[aliases.home]\n", encoding="utf-8")
            xdg_config.write_text("[aliases.xdg]\n", encoding="utf-8")

            old_cwd = Path.cwd()
            try:
                os.chdir(nested)
                with mock.patch.dict(
                    os.environ,
                    {
                        "HOME": str(tmp_path / "home"),
                        "XDG_CONFIG_HOME": str(tmp_path / "xdg"),
                        "CCC_CONFIG": str(tmp_path / "custom.toml"),
                    },
                    clear=False,
                ):
                    self.assertEqual(find_alias_write_path(global_only=True), xdg_config)
            finally:
                os.chdir(old_cwd)


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
            "cursor",
            "cu",
        ]:
            self.assertIn(sel, RUNNER_REGISTRY, f"Missing selector: {sel}")

    def test_abbreviations_point_to_same_info(self):
        self.assertIs(RUNNER_REGISTRY["oc"], RUNNER_REGISTRY["opencode"])
        self.assertIs(RUNNER_REGISTRY["cc"], RUNNER_REGISTRY["claude"])
        self.assertIs(RUNNER_REGISTRY["c"], RUNNER_REGISTRY["codex"])
        self.assertIs(RUNNER_REGISTRY["cx"], RUNNER_REGISTRY["codex"])
        self.assertIs(RUNNER_REGISTRY["k"], RUNNER_REGISTRY["kimi"])
        self.assertIs(RUNNER_REGISTRY["rc"], RUNNER_REGISTRY["roocode"])
        self.assertIs(RUNNER_REGISTRY["cr"], RUNNER_REGISTRY["crush"])
        self.assertIs(RUNNER_REGISTRY["cu"], RUNNER_REGISTRY["cursor"])


if __name__ == "__main__":
    unittest.main()

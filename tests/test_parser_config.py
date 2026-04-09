import unittest
import tempfile
from pathlib import Path

from call_coding_clis.parser import (
    parse_args,
    resolve_command,
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
        self.assertIsNone(parsed.provider)
        self.assertIsNone(parsed.model)
        self.assertIsNone(parsed.alias)

    def test_runner_selector_cc(self):
        parsed = parse_args(["cc", "fix bug"])
        self.assertEqual(parsed.runner, "cc")
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
            "+high": 3,
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

    def test_full_combo(self):
        parsed = parse_args(["cc", "+3", ":anthropic:claude-4", "@fast", "fix tests"])
        self.assertEqual(parsed.runner, "cc")
        self.assertEqual(parsed.thinking, 3)
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
        self.assertEqual(argv[0], "claude")
        self.assertNotIn("run", argv)
        self.assertIn("hello", argv)
        self.assertEqual(warnings, [])

    def test_thinking_flags_for_claude(self):
        parsed = ParsedArgs(runner="cc", thinking=2, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertIn("--thinking", argv)
        self.assertIn("medium", argv)

    def test_thinking_zero_for_claude(self):
        parsed = ParsedArgs(runner="cc", thinking=0, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertIn("--no-thinking", argv)

    def test_xhigh_for_claude_uses_max_flag(self):
        parsed = parse_args(["cc", "+xhigh", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertIn("--thinking", argv)
        self.assertIn("max", argv)

    def test_max_for_kimi_uses_max_flag(self):
        parsed = parse_args(["k", "+max", "hello"])
        argv, _env, _warnings = resolve_command(parsed)
        self.assertIn("--think", argv)
        self.assertIn("max", argv)

    def test_model_flag_for_claude(self):
        parsed = ParsedArgs(runner="cc", model="claude-4", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertIn("--model", argv)
        self.assertIn("claude-4", argv)

    def test_provider_sets_env(self):
        parsed = ParsedArgs(provider="anthropic", prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertEqual(env.get("CCC_PROVIDER"), "anthropic")

    def test_empty_prompt_raises(self):
        parsed = ParsedArgs(prompt="   ")
        with self.assertRaises(ValueError):
            resolve_command(parsed)

    def test_config_default_runner(self):
        config = CccConfig(default_runner="cc")
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(argv[0], "claude")

    def test_config_default_thinking(self):
        config = CccConfig(default_runner="cc", default_thinking=1)
        parsed = ParsedArgs(prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertIn("--thinking", argv)
        self.assertIn("low", argv)

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
        self.assertEqual(argv[0], "claude")
        self.assertIn("--thinking", argv)
        self.assertIn("high", argv)
        self.assertIn("--model", argv)
        self.assertIn("claude-4", argv)
        self.assertEqual(warnings, [])

    def test_explicit_overrides_alias(self):
        config = CccConfig(
            aliases={"work": AliasDef(runner="cc", thinking=3, model="claude-4")}
        )
        parsed = ParsedArgs(runner="k", alias="work", thinking=1, prompt="hello")
        argv, env, _warnings = resolve_command(parsed, config)
        self.assertEqual(argv[0], "kimi")
        self.assertIn("--think", argv)
        self.assertIn("low", argv)

    def test_kimi_thinking_flags(self):
        parsed = ParsedArgs(runner="k", thinking=4, prompt="hello")
        argv, env, _warnings = resolve_command(parsed)
        self.assertIn("--think", argv)
        self.assertIn("max", argv)

    def test_alias_falls_back_to_agent_for_opencode(self):
        parsed = ParsedArgs(alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:4], ["opencode", "run", "--agent", "reviewer"])
        self.assertEqual(env, {})
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_claude(self):
        parsed = ParsedArgs(runner="cc", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["claude", "--agent", "reviewer"])
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_for_kimi(self):
        parsed = ParsedArgs(runner="k", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[:3], ["kimi", "--agent", "reviewer"])
        self.assertEqual(warnings, [])

    def test_alias_falls_back_to_agent_with_warning_when_runner_lacks_support(self):
        parsed = ParsedArgs(runner="rc", alias="reviewer", prompt="hello")
        argv, env, warnings = resolve_command(parsed)
        self.assertEqual(argv[0], "codex")
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
thinking = 2

[abbreviations]
mycc = "cc"

[aliases.work]
runner = "cc"
thinking = 3
model = "claude-4"
agent = "reviewer"

[aliases.quick]
runner = "oc"
""")
            f.flush()
            config = load_config(f.name)

        self.assertEqual(config.default_runner, "cc")
        self.assertEqual(config.default_provider, "anthropic")
        self.assertEqual(config.default_model, "claude-4")
        self.assertEqual(config.default_thinking, 2)
        self.assertEqual(config.abbreviations, {"mycc": "cc"})
        self.assertIn("work", config.aliases)
        self.assertEqual(config.aliases["work"].runner, "cc")
        self.assertEqual(config.aliases["work"].thinking, 3)
        self.assertEqual(config.aliases["work"].model, "claude-4")
        self.assertEqual(config.aliases["work"].agent, "reviewer")
        self.assertIn("quick", config.aliases)
        self.assertEqual(config.aliases["quick"].runner, "oc")

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
            "k",
            "rc",
            "cr",
            "codex",
            "claude",
            "opencode",
            "kimi",
            "crush",
        ]:
            self.assertIn(sel, RUNNER_REGISTRY, f"Missing selector: {sel}")

    def test_abbreviations_point_to_same_info(self):
        self.assertIs(RUNNER_REGISTRY["oc"], RUNNER_REGISTRY["opencode"])
        self.assertIs(RUNNER_REGISTRY["cc"], RUNNER_REGISTRY["claude"])
        self.assertIs(RUNNER_REGISTRY["c"], RUNNER_REGISTRY["claude"])
        self.assertIs(RUNNER_REGISTRY["k"], RUNNER_REGISTRY["kimi"])


if __name__ == "__main__":
    unittest.main()

import unittest

from call_coding_clis.config import load_config
from call_coding_clis.model_fallback import (
    assistant_output_started,
    failure_allows_fallback,
    plan_model_fallback,
)
from call_coding_clis.parser import CccConfig, ParsedArgs, parse_args


class ModelFallbackDecisionTests(unittest.TestCase):
    def test_capacity_before_output_may_fall_back(self) -> None:
        self.assertTrue(
            failure_allows_fallback(
                1,
                False,
                "",
                "Selected model is at capacity. Please try a different model.\n",
            )
        )

    def test_auth_error_does_not_fall_back(self) -> None:
        self.assertFalse(
            failure_allows_fallback(
                1,
                False,
                "",
                "unexpected status 401 Unauthorized: OpenAI account pool has no usable account credential\n",
            )
        )

    def test_assistant_output_blocks_fallback(self) -> None:
        self.assertTrue(assistant_output_started("partial answer\n"))
        self.assertFalse(
            failure_allows_fallback(
                1,
                False,
                "partial answer\n",
                "Selected model is at capacity\n",
            )
        )

    def test_error_only_json_is_not_assistant_output(self) -> None:
        stdout = (
            '{"type":"thread.started","thread_id":"t"}\n'
            '{"type":"error","message":"Selected model is at capacity"}\n'
            '{"type":"turn.failed","error":{"message":"server_overloaded"}}\n'
        )
        self.assertFalse(assistant_output_started(stdout))
        self.assertTrue(failure_allows_fallback(1, False, stdout, ""))

    def test_plan_skips_claude_runner_and_minimax_models(self) -> None:
        from call_coding_clis.parser import AliasDef

        config = CccConfig()
        config.aliases["claude-review"] = AliasDef(
            runner="claude",
            model="claude-sonnet",
            fallback_models=["gpt-6-sol"],
        )
        claude_plan = plan_model_fallback(
            parse_args(["@claude-review", "hello"]), config
        )
        self.assertEqual(claude_plan.models, ["claude-sonnet"])
        self.assertFalse(claude_plan.announce)
        self.assertIn("ignoring fallback_models", claude_plan.pre_notices[0])

        config.aliases["cx"] = AliasDef(
            runner="codex",
            model="gpt-6.1-sol",
            fallback_models=["MiniMax-M3", "gpt-6-astra", "gpt-6-sol"],
        )
        codex_plan = plan_model_fallback(parse_args(["@cx", "hello"]), config)
        self.assertEqual(codex_plan.models, ["gpt-6.1-sol", "gpt-6-sol"])
        self.assertEqual(codex_plan.runners, ["codex", "codex"])
        self.assertTrue(codex_plan.announce)
        self.assertIn("MiniMax-M3", codex_plan.pre_notices[0])
        self.assertIn("gpt-6-astra", codex_plan.pre_notices[1])

    def test_primary_astra_stays_and_glm_switches_runner(self) -> None:
        from dataclasses import replace

        from call_coding_clis.parser import AliasDef, resolve_command

        config = CccConfig()
        config.aliases["cx-astra"] = AliasDef(
            runner="codex",
            model="gpt-6-astra",
            thinking=4,
            show_thinking=False,
            output_mode="stream-text",
            fallback_models=["glm-5.3", "GPT-6-Astra--fast", "llmp-glm-5-3"],
        )
        parsed = parse_args(["@cx-astra", "ping"])
        plan = plan_model_fallback(parsed, config)
        self.assertEqual(plan.models, ["gpt-6-astra", "glm-5.3", "llmp-glm-5-3"])
        self.assertEqual(plan.runners, ["codex", "grok", "grok"])
        self.assertIn("GPT-6-Astra--fast", plan.pre_notices[0])
        overridden = replace(parsed, runner="grok", model="glm-5.3")
        argv, _env, _warnings = resolve_command(overridden, config)
        self.assertEqual(argv[0], "grok")
        model_at = argv.index("--model")
        self.assertEqual(argv[model_at + 1], "glm-5.3")
        effort_at = argv.index("--reasoning-effort")
        self.assertEqual(argv[effort_at + 1], "xhigh")
        self.assertIn("-p", argv)
        self.assertNotIn("exec", argv)

    def test_load_config_reads_fallback_models(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.toml"
            path.write_text(
                '[aliases.cx-reviewer]\nrunner = "codex"\nmodel = "gpt-6.1-sol"\n'
                'fallback_models = ["gpt-6-astra", "gpt-6-sol"]\n',
                encoding="utf-8",
            )
            config = load_config(path)
        alias = config.aliases["cx-reviewer"]
        self.assertEqual(alias.fallback_models, ["gpt-6-astra", "gpt-6-sol"])
        parsed = ParsedArgs(alias="cx-reviewer", prompt="hello", prompt_supplied=True)
        plan = plan_model_fallback(parsed, config)
        self.assertEqual(plan.models, ["gpt-6.1-sol", "gpt-6-sol"])
        self.assertEqual(plan.runners, ["codex", "codex"])
        self.assertIn("gpt-6-astra", plan.pre_notices[0])


if __name__ == "__main__":
    unittest.main()

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
            fallback_models=["MiniMax-M3", "gpt-6-astra", "gpt-6.1-sol"],
        )
        codex_plan = plan_model_fallback(parse_args(["@cx", "hello"]), config)
        self.assertEqual(codex_plan.models, ["gpt-6.1-sol", "gpt-6-astra"])
        self.assertTrue(codex_plan.announce)
        self.assertIn("MiniMax-M3", codex_plan.pre_notices[0])

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
        self.assertEqual(plan.models, ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol"])


if __name__ == "__main__":
    unittest.main()

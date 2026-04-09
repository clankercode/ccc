import subprocess
import unittest
from unittest import mock
from call_coding_clis.cli import (
    _filtered_human_stderr,
    _sanitize_human_output,
    _sanitize_raw_output,
)


class RunnerTests(unittest.TestCase):
    def test_filtered_human_stderr_strips_kimi_resume_hint(self) -> None:
        stderr = "\nTo resume this session: kimi -r 123e4567-e89b-12d3-a456-426614174000\n"
        self.assertEqual(_filtered_human_stderr(stderr, "k"), "")

    def test_filtered_human_stderr_keeps_other_runners(self) -> None:
        stderr = "warning: something else\n"
        self.assertEqual(_filtered_human_stderr(stderr, "cc"), stderr)

    def test_sanitize_raw_output_strips_opencode_osc_title(self) -> None:
        stdout = (
            '{"type":"text","part":{"text":"alpha"}}\n'
            "\x1b]9;OC | call-coding-clis: Agent finished: alpha\x07"
        )
        self.assertEqual(
            _sanitize_raw_output(stdout, "oc"),
            '{"type":"text","part":{"text":"alpha"}}\n',
        )

    def test_sanitize_raw_output_keeps_other_runners(self) -> None:
        stdout = "plain output\n"
        self.assertEqual(_sanitize_raw_output(stdout, "cc"), stdout)

    def test_sanitize_human_output_strips_title_and_bell(self) -> None:
        text = "hello\x1b]9;title here\x07world\a!\n"
        self.assertEqual(_sanitize_human_output(text, True), "helloworld!\n")

    def test_sanitize_human_output_preserves_osc8_hyperlink(self) -> None:
        link = "\x1b]8;;https://example.com\x07click\x1b]8;;\x07"
        self.assertEqual(_sanitize_human_output(link, True), link)

    def test_sanitize_human_output_can_be_disabled(self) -> None:
        text = "hello\x1b]9;title here\x07world\a!\n"
        self.assertEqual(_sanitize_human_output(text, False), text)

    def test_imports_public_api(self) -> None:
        from call_coding_clis import CommandSpec, CompletedRun, Runner

        self.assertIsNotNone(CommandSpec)
        self.assertIsNotNone(CompletedRun)
        self.assertIsNotNone(Runner)

    def test_run_returns_completed_result(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        process_result = mock.Mock(returncode=0, stdout="ok", stderr="")
        executor = mock.Mock(return_value=process_result)

        result = Runner(executor=executor).run(CommandSpec(argv=["fake", "--json"]))

        self.assertEqual(result.argv, ["fake", "--json"])
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.stdout, "ok")
        self.assertEqual(result.stderr, "")
        executor.assert_called_once()

    def test_run_uses_stdin_and_env(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        process_result = mock.Mock(returncode=0, stdout="", stderr="")
        executor = mock.Mock(return_value=process_result)

        Runner(executor=executor).run(
            CommandSpec(
                argv=["fake"],
                stdin_text="hello",
                env={"MODEL": "glm-5.1"},
                cwd="/tmp/work",
            )
        )

        _, kwargs = executor.call_args
        self.assertEqual(kwargs["input"], "hello")
        self.assertIs(kwargs["stdin"], subprocess.PIPE)
        self.assertEqual(kwargs["env"]["MODEL"], "glm-5.1")
        self.assertEqual(kwargs["cwd"], "/tmp/work")

    def test_run_uses_devnull_when_stdin_is_absent(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        process_result = mock.Mock(returncode=0, stdout="", stderr="")
        executor = mock.Mock(return_value=process_result)

        Runner(executor=executor).run(CommandSpec(argv=["fake"]))

        _, kwargs = executor.call_args
        self.assertIs(kwargs["stdin"], subprocess.DEVNULL)

    def test_stream_emits_stdout_and_stderr_events(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        events = []

        def fake_stream_executor(spec, callback):
            callback("stdout", "hello")
            callback("stderr", "warn")
            return mock.Mock(returncode=2)

        result = Runner(stream_executor=fake_stream_executor).stream(
            CommandSpec(argv=["fake"]),
            lambda channel, chunk: events.append((channel, chunk)),
        )

        self.assertEqual(events, [("stdout", "hello"), ("stderr", "warn")])
        self.assertEqual(result.exit_code, 2)

    def test_run_reports_missing_binary_start_failure(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        result = Runner().run(CommandSpec(argv=["/definitely/missing/runner-binary"]))

        self.assertNotEqual(result.exit_code, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("failed to start", result.stderr)
        self.assertIn("runner-binary", result.stderr)

    def test_stream_reports_missing_binary_start_failure(self) -> None:
        from call_coding_clis import CommandSpec, Runner

        events = []
        result = Runner().stream(
            CommandSpec(argv=["/definitely/missing/runner-binary"]),
            lambda channel, chunk: events.append((channel, chunk)),
        )

        self.assertNotEqual(result.exit_code, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("failed to start", result.stderr)
        self.assertIn("runner-binary", result.stderr)
        self.assertEqual(events, [("stderr", result.stderr)])

    def test_ccc_builds_prompt_command_spec(self) -> None:
        from call_coding_clis.cli import build_prompt_spec

        spec = build_prompt_spec("Fix the failing tests")

        self.assertEqual(spec.argv, ["opencode", "run", "Fix the failing tests"])

    def test_ccc_rejects_empty_prompt(self) -> None:
        from call_coding_clis.cli import build_prompt_spec

        with self.assertRaises(ValueError):
            build_prompt_spec("   ")

    def test_ccc_help_mentions_show_thinking(self) -> None:
        from call_coding_clis.help import HELP_TEXT

        self.assertIn("--show-thinking", HELP_TEXT)
        self.assertIn("--sanitize-osc", HELP_TEXT)
        self.assertIn("--output-mode", HELP_TEXT)
        self.assertIn("--forward-unknown-json", HELP_TEXT)
        self.assertIn(".json / ..json", HELP_TEXT)
        self.assertIn("--permission-mode <safe|auto|yolo|plan>", HELP_TEXT)
        self.assertIn("--yolo / -y", HELP_TEXT)
        self.assertIn("Treat all remaining args as prompt text", HELP_TEXT)
        self.assertIn("show_thinking", HELP_TEXT)


if __name__ == "__main__":
    unittest.main()

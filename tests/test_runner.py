import subprocess
import unittest
from unittest import mock


class RunnerTests(unittest.TestCase):
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
        self.assertIn("show_thinking", HELP_TEXT)


if __name__ == "__main__":
    unittest.main()

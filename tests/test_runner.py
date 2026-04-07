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
        self.assertEqual(kwargs["env"]["MODEL"], "glm-5.1")
        self.assertEqual(kwargs["cwd"], "/tmp/work")

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


if __name__ == "__main__":
    unittest.main()

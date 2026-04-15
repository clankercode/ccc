from __future__ import annotations

import io
import os
import re
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest import mock

from call_coding_clis import cli
from call_coding_clis.artifacts import (
    RunArtifactWriter,
    create_run_artifact_writer,
    create_run_directory,
    resolve_state_root,
)
from call_coding_clis.help import HELP_TEXT
from call_coding_clis.parser import parse_args
from call_coding_clis.runner import CompletedRun


OPENCODE_STREAM_JSON = '{"response":"Hello from OpenCode"}\n'
OPENCODE_STREAM_JSON_WITH_SESSION = (
    '{"response":"Hello from OpenCode","sessionID":"session-1"}\n'
)


class FakeRunner:
    def __init__(
        self,
        *,
        stream_events: list[tuple[str, str]] | None = None,
        stdout: str = "",
        stderr: str = "",
        exit_code: int = 0,
    ) -> None:
        self.stream_events = stream_events or [("stdout", stdout)]
        self.stdout = stdout
        self.stderr = stderr
        self.exit_code = exit_code
        self.last_spec = None

    def run(self, spec):
        self.last_spec = spec
        return CompletedRun(
            argv=list(spec.argv),
            exit_code=self.exit_code,
            stdout=self.stdout,
            stderr=self.stderr,
        )

    def stream(self, spec, on_event):
        self.last_spec = spec
        for channel, chunk in self.stream_events:
            on_event(channel, chunk)
        return CompletedRun(
            argv=list(spec.argv),
            exit_code=self.exit_code,
            stdout=self.stdout,
            stderr=self.stderr,
        )


class FlakyWriter:
    def __init__(self, run_dir: Path, transcript_name: str = "transcript.txt") -> None:
        self.run_dir = run_dir
        self.output_path = run_dir / "output.txt"
        self.transcript_path = run_dir / transcript_name
        self.transcript_path.write_text("", encoding="utf-8")
        self.footer_enabled = True
        self.transcript_warning = None
        self._transcript_text = ""

    def write_transcript(self, text: str) -> None:
        self._transcript_text += text
        self.transcript_path.write_text(self._transcript_text, encoding="utf-8")

    def write_output(self, text: str) -> None:
        raise OSError("disk full")

    def close(self) -> None:
        return None

    def footer_line(self) -> str:
        return f">> ccc:output-log >> {self.run_dir}"


def _footer_path(stderr: str) -> Path:
    match = re.search(r"^>> ccc:output-log >> (.+)$", stderr, re.MULTILINE)
    assert match is not None, stderr
    return Path(match.group(1))


def _run_cli(
    args: list[str],
    *,
    fake_runner: FakeRunner | None = None,
    env: dict[str, str] | None = None,
    writer=None,
) -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    merged_env = {"CCC_REAL_OPENCODE": ""}
    if env:
        merged_env.update(env)
    with mock.patch.dict(os.environ, merged_env, clear=False):
        with ExitStack() as stack:
            if fake_runner is not None:
                stack.enter_context(
                    mock.patch("call_coding_clis.cli.Runner", return_value=fake_runner)
                )
            if writer is not None:
                stack.enter_context(
                    mock.patch(
                        "call_coding_clis.cli.artifacts.create_run_artifact_writer",
                        return_value=writer,
                    )
                )
            stack.enter_context(mock.patch("sys.stdout", stdout))
            stack.enter_context(mock.patch("sys.stderr", stderr))
            rc = cli.main(args)
    return rc, stdout.getvalue(), stderr.getvalue()


class StateRootResolutionTests(unittest.TestCase):
    def test_prefers_xdg_state_home(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": "/tmp/state"}, clear=True):
            self.assertEqual(resolve_state_root(), Path("/tmp/state"))

    def test_uses_macos_application_support(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            with mock.patch.object(cli.artifacts.sys, "platform", "darwin"):
                with mock.patch.object(
                    cli.artifacts.Path,
                    "home",
                    return_value=Path("/Users/tester"),
                ):
                    self.assertEqual(
                        resolve_state_root(),
                        Path("/Users/tester/Library/Application Support"),
                    )

    def test_uses_localappdata_on_windows(self) -> None:
        with mock.patch.dict(
            os.environ, {"LOCALAPPDATA": r"C:\\Users\\tester\\AppData\\Local"}, clear=True
        ):
            with mock.patch.object(cli.artifacts.sys, "platform", "win32"):
                self.assertEqual(
                    resolve_state_root(),
                    Path(r"C:\\Users\\tester\\AppData\\Local"),
                )


class RunDirectoryTests(unittest.TestCase):
    def test_run_directory_creation_retries_on_collision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_root = Path(tmp)
            existing = state_root / "ccc" / "runs" / "collision"
            existing.mkdir(parents=True)

            factory = mock.Mock(side_effect=["collision", "fresh-run"])
            run_dir = create_run_directory(state_root, run_id_factory=factory)

            self.assertEqual(run_dir, state_root / "ccc" / "runs" / "fresh-run")
            self.assertTrue(run_dir.exists())
            self.assertEqual(factory.call_count, 2)

    def test_run_directory_creation_prefixes_runner_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_root = Path(tmp)
            run_dir = create_run_directory(
                state_root,
                run_id_factory=lambda: "fresh-run",
                run_dir_prefix="g",
            )

            self.assertEqual(run_dir, state_root / "ccc" / "runs" / "gemini-fresh-run")
            self.assertTrue(run_dir.exists())


class ParserAndHelpTests(unittest.TestCase):
    def test_parse_args_supports_output_log_flags(self) -> None:
        parsed = parse_args(["--no-output-log-path", "--output-log-path", "hello"])
        self.assertTrue(parsed.output_log_path)

        parsed = parse_args(["--output-log-path", "--no-output-log-path", "hello"])
        self.assertFalse(parsed.output_log_path)

    def test_help_mentions_output_log_flags(self) -> None:
        self.assertIn("--output-log-path / --no-output-log-path", HELP_TEXT)
        self.assertIn("No TOML config key", HELP_TEXT)


class CccRunArtifactCliTests(unittest.TestCase):
    def test_stream_formatted_writes_transcript_txt_and_output_txt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "..fmt", "Hello"],
                fake_runner=fake_runner,
                env={"XDG_STATE_HOME": tmp},
            )

            run_dir = _footer_path(stderr_text)

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertTrue(run_dir.is_dir())
            self.assertTrue(run_dir.name.startswith("opencode-"), run_dir)
            self.assertEqual(
                (run_dir / "output.txt").read_text(encoding="utf-8"),
                "Hello from OpenCode",
            )
            self.assertEqual(
                (run_dir / "transcript.txt").read_text(encoding="utf-8"),
                "[assistant] Hello from OpenCode\n",
            )
            self.assertFalse((run_dir / "transcript.jsonl").exists())
            self.assertTrue(stderr_text.rstrip().endswith(f">> ccc:output-log >> {run_dir}"))

    def test_text_upgrade_path_still_uses_transcript_txt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "Hello"],
                fake_runner=fake_runner,
                env={"XDG_STATE_HOME": tmp},
            )

            run_dir = _footer_path(stderr_text)

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertTrue(run_dir.name.startswith("opencode-"), run_dir)
            self.assertTrue((run_dir / "transcript.txt").exists())
            self.assertFalse((run_dir / "transcript.jsonl").exists())
            self.assertEqual(
                (run_dir / "output.txt").read_text(encoding="utf-8"),
                "Hello from OpenCode",
            )

    def test_stream_json_writes_transcript_jsonl_and_output_txt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "-o", "stream-json", "Hello"],
                fake_runner=fake_runner,
                env={"XDG_STATE_HOME": tmp},
            )

            run_dir = _footer_path(stderr_text)

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, OPENCODE_STREAM_JSON)
            self.assertTrue(run_dir.name.startswith("opencode-"), run_dir)
            self.assertTrue((run_dir / "transcript.jsonl").exists())
            self.assertFalse((run_dir / "transcript.txt").exists())
            self.assertEqual(
                (run_dir / "transcript.jsonl").read_text(encoding="utf-8"),
                OPENCODE_STREAM_JSON,
            )
            self.assertEqual(
                (run_dir / "output.txt").read_text(encoding="utf-8"),
                "Hello from OpenCode",
            )

    def test_no_output_log_path_suppresses_only_footer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "--no-output-log-path", "Hello"],
                fake_runner=fake_runner,
                env={"XDG_STATE_HOME": tmp},
            )

            run_root = Path(tmp) / "ccc" / "runs"
            run_dirs = list(run_root.iterdir())

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertEqual(stderr_text, "")
            self.assertEqual(len(run_dirs), 1)
            self.assertTrue(run_dirs[0].name.startswith("opencode-"), run_dirs[0])
            self.assertTrue((run_dirs[0] / "output.txt").exists())
            self.assertTrue((run_dirs[0] / "transcript.txt").exists())

    def test_footer_follows_cleanup_warning(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON_WITH_SESSION)],
                stdout=OPENCODE_STREAM_JSON_WITH_SESSION,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--cleanup-session", "Hello"],
                fake_runner=fake_runner,
                env={"XDG_STATE_HOME": tmp},
            )

            footer = f">> ccc:output-log >> {_footer_path(stderr_text)}"

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertIn("warning: failed to cleanup OpenCode session", stderr_text)
            self.assertTrue(_footer_path(stderr_text).name.startswith("opencode-"))
            self.assertTrue(stderr_text.rstrip().endswith(footer))

    def test_directory_creation_failure_skips_footer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            with mock.patch(
                "call_coding_clis.cli.artifacts.create_run_artifact_writer",
                return_value=None,
            ):
                rc, stdout_text, stderr_text = _run_cli(
                    ["oc", "--save-session", "Hello"],
                    fake_runner=fake_runner,
                    env={"XDG_STATE_HOME": tmp},
                )

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertNotIn("ccc:output-log", stderr_text)
            self.assertFalse(list((Path(tmp) / "ccc" / "runs").glob("*")))

    def test_file_write_failure_still_leaves_other_artifact_and_footer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "ccc" / "runs" / "run-1"
            run_dir.mkdir(parents=True)
            writer = FlakyWriter(run_dir)
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "Hello"],
                fake_runner=fake_runner,
                writer=writer,
                env={"XDG_STATE_HOME": tmp},
            )

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertIn("warning: could not write output.txt:", stderr_text)
            self.assertTrue((run_dir / "transcript.txt").exists())
            self.assertFalse((run_dir / "output.txt").exists())
            self.assertTrue(stderr_text.rstrip().endswith(f">> ccc:output-log >> {run_dir}"))

    def test_transcript_creation_failure_warns_but_keeps_footer_and_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "ccc" / "runs" / "run-1"
            run_dir.mkdir(parents=True)
            fake_runner = FakeRunner(
                stream_events=[("stdout", OPENCODE_STREAM_JSON)],
                stdout=OPENCODE_STREAM_JSON,
                stderr="",
            )
            writer = RunArtifactWriter(
                run_dir=run_dir,
                transcript_name="transcript.txt",
                transcript_warning="warning: could not create transcript.txt: permission denied",
            )
            rc, stdout_text, stderr_text = _run_cli(
                ["oc", "--save-session", "Hello"],
                fake_runner=fake_runner,
                writer=writer,
                env={"XDG_STATE_HOME": tmp},
            )

            run_dir = _footer_path(stderr_text)

            self.assertEqual(rc, 0, stderr_text)
            self.assertEqual(stdout_text, "[assistant] Hello from OpenCode\n")
            self.assertIn("warning: could not create transcript.txt:", stderr_text)
            self.assertTrue((run_dir / "output.txt").exists())
            self.assertFalse((run_dir / "transcript.txt").exists())
            self.assertTrue(stderr_text.rstrip().endswith(f">> ccc:output-log >> {run_dir}"))


if __name__ == "__main__":
    unittest.main()

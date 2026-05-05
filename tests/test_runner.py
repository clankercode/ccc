import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import io
from call_coding_clis import cli
from call_coding_clis.cli import (
    main,
    _apply_real_runner_override,
    _cleanup_runner_session,
    _extract_kimi_resume_session_id,
    _extract_opencode_session_id,
    _filtered_human_stderr,
    _sanitize_human_output,
    _sanitize_raw_output,
    _session_persistence_pre_run_warnings,
)
from call_coding_clis.help import _get_runner_version
from call_coding_clis.help import RunnerStatus, _format_version_report


FIXTURE_CONFIG_PATH = Path(__file__).parent / "fixtures" / "config-example.toml"


def read_example_config_fixture() -> str:
    return FIXTURE_CONFIG_PATH.read_text(encoding="utf-8")


class RunnerTests(unittest.TestCase):
    def test_formatted_mode_with_show_thinking_surfaces_opencode_tool_work(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_path = tmp_path / "ccc-config.toml"
            config_path.write_text("", encoding="utf-8")

            env = os.environ.copy()
            env["PYTHONPATH"] = "python"
            env["MOCK_JSON_SCHEMA"] = "opencode"
            env["CCC_REAL_OPENCODE"] = str(
                Path(__file__).resolve().parent
                / "mock-coding-cli"
                / "mock_coding_cli.sh"
            )
            env["CCC_CONFIG"] = str(config_path)
            env["HOME"] = str(tmp_path / "home")
            env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")

            with mock.patch.dict(os.environ, env, clear=False):
                with mock.patch("sys.stdout.isatty", return_value=False):
                    with mock.patch("sys.stderr.isatty", return_value=False):
                        with mock.patch(
                            "sys.argv",
                            ["ccc", "oc", "..fmt", "--show-thinking", "tool call"],
                        ):
                            with mock.patch("sys.stdout") as stdout:
                                with mock.patch("sys.stderr") as stderr:
                                    rc = main(
                                        ["oc", "..fmt", "--show-thinking", "tool call"]
                                    )

        self.assertEqual(rc, 0)
        rendered_stdout = "".join(call.args[0] for call in stdout.write.call_args_list)
        rendered_stderr = "".join(call.args[0] for call in stderr.write.call_args_list)
        self.assertIn("read", rendered_stdout)
        self.assertIn("read (ok)", rendered_stdout)
        self.assertIn("mock: tool call executed", rendered_stdout)
        self.assertIn(
            'warning: runner "opencode" may save this session', rendered_stderr
        )

    def test_runner_version_reads_opencode_package_json_before_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "node_modules" / "opencode-ai"
            binary_path = package_root / "bin" / "opencode"
            binary_path.parent.mkdir(parents=True)
            (package_root / "package.json").write_text(
                '{"name":"opencode-ai","version":"1.2.3"}',
                encoding="utf-8",
            )
            binary_path.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")

            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version("opencode", "opencode", str(binary_path))

            self.assertEqual(version, "1.2.3")
            fallback.assert_not_called()

    def test_runner_version_reads_codex_package_json_before_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_root = root / "node_modules" / "@openai" / "codex"
            binary_path = package_root / "bin" / "codex.js"
            binary_path.parent.mkdir(parents=True)
            (package_root / "package.json").write_text(
                '{"name":"@openai/codex","version":"0.118.0"}',
                encoding="utf-8",
            )
            binary_path.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")

            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version("codex", "codex", str(binary_path))

            self.assertEqual(version, "codex-cli 0.118.0")
            fallback.assert_not_called()

    def test_runner_version_reads_claude_version_from_install_path(self) -> None:
        with mock.patch(
            "os.path.realpath", return_value="/tmp/.local/share/claude/versions/2.1.98"
        ):
            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version("claude", "claude", "/tmp/bin/claude")

        self.assertEqual(version, "2.1.98 (Claude Code)")
        fallback.assert_not_called()

    def test_runner_version_reads_kimi_metadata_before_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary_path = root / "bin" / "kimi"
            metadata_dir = (
                root
                / "lib"
                / "python3.13"
                / "site-packages"
                / "kimi_cli-1.30.0.dist-info"
            )
            binary_path.parent.mkdir(parents=True)
            metadata_dir.mkdir(parents=True)
            binary_path.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
            (metadata_dir / "METADATA").write_text(
                "Metadata-Version: 2.3\nName: kimi-cli\nVersion: 1.30.0\n",
                encoding="utf-8",
            )

            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version("kimi", "kimi", str(binary_path))

            self.assertEqual(version, "kimi, version 1.30.0")
            fallback.assert_not_called()

    def test_runner_version_reads_cursor_release_marker_before_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp) / "cursor-agent"
            binary_path = package_root / "cursor-agent"
            package_root.mkdir(parents=True)
            (package_root / "package.json").write_text(
                '{"name":"@anysphere/agent-cli-runtime","private":true}',
                encoding="utf-8",
            )
            (package_root / "index.js").write_text(
                'globalThis.SENTRY_RELEASE={id:"agent-cli@2026.03.30-a5d3e17"};',
                encoding="utf-8",
            )
            binary_path.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")

            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version(
                    "cursor", "cursor-agent", str(binary_path)
                )

            self.assertEqual(version, "2026.03.30-a5d3e17")
            fallback.assert_not_called()

    def test_runner_version_reads_gemini_package_json_before_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp) / "node_modules" / "@google" / "gemini-cli"
            binary_path = package_root / "dist" / "index.js"
            binary_path.parent.mkdir(parents=True)
            (package_root / "package.json").write_text(
                '{"name":"@google/gemini-cli","version":"0.37.2"}',
                encoding="utf-8",
            )
            binary_path.write_text("#!/usr/bin/env node\n", encoding="utf-8")

            with mock.patch("call_coding_clis.help._get_version") as fallback:
                version = _get_runner_version("gemini", "gemini", str(binary_path))

            self.assertEqual(version, "0.37.2")
            fallback.assert_not_called()

    def test_runner_version_identifies_gemini_npx_launcher_without_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary_path = Path(tmp) / "gemini"
            binary_path.write_text(
                '#!/bin/bash\nexec npx --yes @google/gemini-cli "$@"\n',
                encoding="utf-8",
            )

            with mock.patch("call_coding_clis.help.Path.home", return_value=Path(tmp)):
                with mock.patch("call_coding_clis.help._get_version") as fallback:
                    version = _get_runner_version("gemini", "gemini", str(binary_path))

            self.assertEqual(version, "npx @google/gemini-cli")
            fallback.assert_not_called()

    def test_runner_version_falls_back_when_metadata_is_missing(self) -> None:
        with mock.patch(
            "call_coding_clis.help._get_version", return_value="fallback 9.9.9"
        ) as fallback:
            version = _get_runner_version(
                "opencode", "opencode", "/tmp/missing/opencode"
            )

        self.assertEqual(version, "fallback 9.9.9")
        fallback.assert_called_once_with("opencode")

    def test_version_report_lists_resolved_clients_and_summary(self) -> None:
        report = _format_version_report(
            "0.1.2",
            [
                RunnerStatus(
                    name="opencode",
                    alias="oc",
                    binary="opencode",
                    found=True,
                    version="1.3.17",
                ),
                RunnerStatus(
                    name="claude",
                    alias="cc",
                    binary="claude",
                    found=True,
                    version="",
                ),
            ],
        )

        self.assertEqual(
            report,
            "ccc version 0.1.2\n"
            "Resolved clients:\n"
            "  [+] opencode   (opencode)  1.3.17\n"
            "  (and 1 unresolved)",
        )

    def test_filtered_human_stderr_strips_kimi_resume_hint(self) -> None:
        stderr = (
            "\nTo resume this session: kimi -r 123e4567-e89b-12d3-a456-426614174000\n"
        )
        self.assertEqual(_filtered_human_stderr(stderr, "k"), "")

    def test_filtered_human_stderr_keeps_other_runners(self) -> None:
        stderr = "warning: something else\n"
        self.assertEqual(_filtered_human_stderr(stderr, "cc"), stderr)

    def test_extract_opencode_session_id_from_step_start(self) -> None:
        stdout = '{"type":"step_start","sessionID":"ses_123"}\n{"type":"text","part":{"text":"ok"}}\n'
        self.assertEqual(_extract_opencode_session_id(stdout), "ses_123")

    def test_extract_kimi_resume_session_id_from_stderr(self) -> None:
        stderr = (
            "To resume this session: kimi -r 123e4567-e89b-12d3-a456-426614174000\n"
        )
        self.assertEqual(
            _extract_kimi_resume_session_id(stderr),
            "123e4567-e89b-12d3-a456-426614174000",
        )

    def test_cleanup_runner_session_deletes_opencode_session(self) -> None:
        stdout = '{"type":"step_start","sessionID":"ses_123"}\n'
        with mock.patch("subprocess.run") as run:
            run.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            warnings = _cleanup_runner_session(
                runner_name="oc",
                runner_binary="/tmp/mock-opencode",
                stdout=stdout,
                stderr="",
                env={},
            )

        run.assert_called_once()
        args, kwargs = run.call_args
        self.assertEqual(
            args[0], ["/tmp/mock-opencode", "session", "delete", "ses_123"]
        )
        self.assertTrue(kwargs["capture_output"])
        self.assertEqual(warnings, [])

    def test_cleanup_runner_session_deletes_kimi_session_file_from_share_dir(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session_id = "123e4567-e89b-12d3-a456-426614174000"
            session_file = Path(tmp) / "sessions" / "2026" / f"{session_id}.json"
            session_file.parent.mkdir(parents=True)
            session_file.write_text("{}", encoding="utf-8")

            warnings = _cleanup_runner_session(
                runner_name="k",
                runner_binary="kimi",
                stdout="",
                stderr=f"To resume this session: kimi -r {session_id}\n",
                env={"KIMI_SHARE_DIR": tmp},
            )

            self.assertFalse(session_file.exists())
            self.assertEqual(warnings, [])

    def test_cleanup_runner_session_deletes_kimi_session_directory_from_share_dir(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session_id = "123e4567-e89b-12d3-a456-426614174000"
            session_dir = Path(tmp) / "sessions" / "workdir-hash" / session_id
            session_dir.mkdir(parents=True)
            (session_dir / "session.json").write_text("{}", encoding="utf-8")

            warnings = _cleanup_runner_session(
                runner_name="k",
                runner_binary="kimi",
                stdout="",
                stderr=f"To resume this session: kimi -r {session_id}\n",
                env={"KIMI_SHARE_DIR": tmp},
            )

            self.assertFalse(session_dir.exists())
            self.assertEqual(warnings, [])

    def test_cleanup_runner_session_warns_when_session_id_is_missing(self) -> None:
        warnings = _cleanup_runner_session(
            runner_name="oc",
            runner_binary="opencode",
            stdout='{"type":"text","part":{"text":"ok"}}\n',
            stderr="",
            env={},
        )

        self.assertEqual(
            warnings,
            ["warning: could not find OpenCode session ID for cleanup"],
        )

    def test_session_persistence_pre_run_warning_policy(self) -> None:
        warnings = _session_persistence_pre_run_warnings(False, False, "oc")
        self.assertEqual(
            warnings,
            [
                'warning: runner "opencode" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup'
            ],
        )
        self.assertEqual(_session_persistence_pre_run_warnings(True, False, "oc"), [])
        self.assertEqual(_session_persistence_pre_run_warnings(False, True, "oc"), [])
        self.assertEqual(_session_persistence_pre_run_warnings(False, False, "cc"), [])
        self.assertEqual(
            _session_persistence_pre_run_warnings(False, False, "cu"),
            [
                'warning: runner "cursor" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup'
            ],
        )
        self.assertEqual(
            _session_persistence_pre_run_warnings(False, False, "g"),
            [
                'warning: runner "gemini" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup'
            ],
        )

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

    @unittest.skipIf(os.name == "nt", "SIGKILL via /bin/sh -c is POSIX-only")
    def test_run_with_timeout_kills_slow_child(self) -> None:
        import time

        from call_coding_clis import CommandSpec, Runner

        start = time.monotonic()
        result = Runner().run(
            CommandSpec(argv=["/bin/sh", "-c", "sleep 5"], timeout_secs=1)
        )
        elapsed = time.monotonic() - start

        self.assertTrue(result.timed_out)
        self.assertLess(elapsed, 3.0)

    @unittest.skipIf(os.name == "nt", "SIGKILL via /bin/sh -c is POSIX-only")
    def test_stream_with_timeout_kills_slow_child(self) -> None:
        import time

        from call_coding_clis import CommandSpec, Runner

        start = time.monotonic()
        result = Runner().stream(
            CommandSpec(argv=["/bin/sh", "-c", "sleep 5"], timeout_secs=1),
            lambda _channel, _chunk: None,
        )
        elapsed = time.monotonic() - start

        self.assertTrue(result.timed_out)
        self.assertLess(elapsed, 3.0)

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

    def test_apply_real_runner_override_for_claude(self) -> None:
        from call_coding_clis import CommandSpec

        spec = CommandSpec(argv=["claude", "-p", "hello"])
        with mock.patch.dict("os.environ", {"CCC_REAL_CLAUDE": "/tmp/mock-claude"}):
            _apply_real_runner_override(spec)
        self.assertEqual(spec.argv[0], "/tmp/mock-claude")

    def test_apply_real_runner_override_for_kimi(self) -> None:
        from call_coding_clis import CommandSpec

        spec = CommandSpec(argv=["kimi", "--prompt", "hello"])
        with mock.patch.dict("os.environ", {"CCC_REAL_KIMI": "/tmp/mock-kimi"}):
            _apply_real_runner_override(spec)
        self.assertEqual(spec.argv[0], "/tmp/mock-kimi")

    def test_apply_real_runner_override_for_cursor(self) -> None:
        from call_coding_clis import CommandSpec

        spec = CommandSpec(argv=["cursor-agent", "--print", "hello"])
        with mock.patch.dict("os.environ", {"CCC_REAL_CURSOR": "/tmp/mock-cursor"}):
            _apply_real_runner_override(spec)
        self.assertEqual(spec.argv[0], "/tmp/mock-cursor")

    def test_apply_real_runner_override_for_gemini(self) -> None:
        from call_coding_clis import CommandSpec

        spec = CommandSpec(argv=["gemini", "--prompt", "hello"])
        with mock.patch.dict("os.environ", {"CCC_REAL_GEMINI": "/tmp/mock-gemini"}):
            _apply_real_runner_override(spec)
        self.assertEqual(spec.argv[0], "/tmp/mock-gemini")

    def test_ccc_rejects_empty_prompt(self) -> None:
        from call_coding_clis.cli import build_prompt_spec

        with self.assertRaises(ValueError):
            build_prompt_spec("   ")

    def test_print_config_cli_outputs_example_config(self) -> None:
        env = os.environ.copy()
        env["PYTHONPATH"] = "python"
        result = subprocess.run(
            ["python3", "python/call_coding_clis/cli.py", "--print-config"],
            cwd=Path(__file__).resolve().parent.parent,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, read_example_config_fixture())
        self.assertEqual(result.stderr, "")

    def test_print_config_cli_rejects_mixed_usage(self) -> None:
        env = os.environ.copy()
        env["PYTHONPATH"] = "python"
        result = subprocess.run(
            ["python3", "python/call_coding_clis/cli.py", "--print-config", "cc"],
            cwd=Path(__file__).resolve().parent.parent,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("--print-config", result.stderr)

    def test_add_alias_yes_writes_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_path = tmp_path / "xdg" / "ccc" / "config.toml"
            env = {
                "HOME": str(tmp_path / "home"),
                "XDG_CONFIG_HOME": str(tmp_path / "xdg"),
                "CCC_CONFIG": str(tmp_path / "missing.toml"),
            }
            with mock.patch.dict(os.environ, env, clear=False):
                with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                    rc = cli.main(
                        [
                            "add",
                            "mm27",
                            "--runner",
                            "cc",
                            "--model",
                            "claude-4",
                            "--prompt",
                            "Review changes",
                            "--prompt-mode",
                            "default",
                            "--yes",
                        ]
                    )

            self.assertEqual(rc, 0)
            self.assertEqual(
                config_path.read_text(encoding="utf-8"),
                "[aliases.mm27]\n"
                'runner = "cc"\n'
                'model = "claude-4"\n'
                'prompt = "Review changes"\n'
                'prompt_mode = "default"\n',
            )
            self.assertIn(f"Config path: {config_path}", stdout.getvalue())
            self.assertIn("\n✓  Alias @mm27 written\n\n", stdout.getvalue())
            self.assertIn("  [aliases.mm27]\n", stdout.getvalue())

    def test_add_alias_cancel_existing_leaves_file_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_path = tmp_path / "xdg" / "ccc" / "config.toml"
            config_path.parent.mkdir(parents=True)
            original = '[aliases.mm27]\nprompt = "old"\n'
            config_path.write_text(original, encoding="utf-8")
            env = {
                "HOME": str(tmp_path / "home"),
                "XDG_CONFIG_HOME": str(tmp_path / "xdg"),
                "CCC_CONFIG": str(tmp_path / "missing.toml"),
                "FORCE_COLOR": "1",
            }
            with mock.patch.dict(os.environ, env, clear=False):
                with mock.patch("sys.stdin", io.StringIO("3\n")):
                    with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                        rc = cli.main(["add", "mm27"])

            self.assertEqual(rc, 0)
            self.assertEqual(config_path.read_text(encoding="utf-8"), original)
            self.assertIn("Existing alias action", stdout.getvalue())
            self.assertIn("(1-3)", stdout.getvalue())
            self.assertIn("  [m]odify, [r]eplace, [c]ancel", stdout.getvalue())
            self.assertIn("default", stdout.getvalue())
            self.assertIn("choice >", stdout.getvalue())
            self.assertIn("\x1b[", stdout.getvalue())

    def test_add_alias_existing_replace_accepts_numbered_choices(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_path = tmp_path / "xdg" / "ccc" / "config.toml"
            config_path.parent.mkdir(parents=True)
            config_path.write_text('[aliases.mm27]\nprompt = "old"\n', encoding="utf-8")
            env = {
                "HOME": str(tmp_path / "home"),
                "XDG_CONFIG_HOME": str(tmp_path / "xdg"),
                "CCC_CONFIG": str(tmp_path / "missing.toml"),
            }
            answers = "\n".join(
                [
                    "2",  # replace
                    "oc",  # runner
                    "",  # provider
                    "",  # model
                    "3",  # thinking: low
                    "3",  # show_thinking: false
                    "1",  # sanitize_osc: default
                    "2",  # output_mode: text
                    "",  # agent
                    "Fix the failing tests",  # prompt
                    "2",  # prompt_mode: default
                    "1",  # confirm yes
                ]
            )
            with mock.patch.dict(os.environ, env, clear=False):
                with mock.patch("sys.stdin", io.StringIO(answers + "\n")):
                    rc = cli.main(["add", "mm27"])

            self.assertEqual(rc, 0)
            self.assertEqual(
                config_path.read_text(encoding="utf-8"),
                "[aliases.mm27]\n"
                'runner = "oc"\n'
                "thinking = 1\n"
                "show_thinking = false\n"
                'output_mode = "text"\n'
                'prompt = "Fix the failing tests"\n'
                'prompt_mode = "default"\n',
            )

    def test_ccc_help_mentions_show_thinking(self) -> None:
        from call_coding_clis.help import HELP_TEXT

        self.assertIn("--print-config", HELP_TEXT)
        self.assertIn("--show-thinking", HELP_TEXT)
        self.assertIn("--sanitize-osc", HELP_TEXT)
        self.assertIn("--output-mode", HELP_TEXT)
        self.assertIn("--forward-unknown-json", HELP_TEXT)
        self.assertIn(".json / ..json", HELP_TEXT)
        self.assertIn("--permission-mode <safe|auto|yolo|plan>", HELP_TEXT)
        self.assertIn("--yolo / -y", HELP_TEXT)
        self.assertIn("Presets can also define a default prompt", HELP_TEXT)
        self.assertIn("Treat all remaining args as prompt text", HELP_TEXT)
        self.assertIn("show_thinking", HELP_TEXT)
        self.assertIn("Agent tips:", HELP_TEXT)
        self.assertIn("Run `ccc config`", HELP_TEXT)


if __name__ == "__main__":
    unittest.main()

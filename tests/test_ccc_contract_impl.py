import argparse
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tests.test_harness import LanguageSpec, _resolve_selected_languages


PROMPT = "Fix the failing tests"
EXPECTED = f"[assistant] opencode run --format json --thinking {PROMPT}\n"
CONFIG_DEFAULT_RUNNER_EXPECTED = f"claude -p --thinking enabled --effort low {PROMPT}\n"
AGENT_FALLBACK_EXPECTED = f"[assistant] opencode run --format json --thinking --agent reviewer {PROMPT}\n"
PRESET_AGENT_EXPECTED = f"[assistant] opencode run --format json --thinking --agent specialist {PROMPT}\n"
PRESET_PROMPT = "Commit all changes"
PRESET_PROMPT_EXPECTED = f"[assistant] opencode run --format json --thinking {PRESET_PROMPT}\n"
PROJECT_LOCAL_PROMPT_EXPECTED = (
    "kimi --thinking --model xdg-model --prompt Repo prompt\n"
)
CODEX_RUNNER_EXPECTED = f"codex exec {PROMPT}\n"
CODEX_RUNNER_NO_PERSIST_EXPECTED = f"codex exec --ephemeral {PROMPT}\n"
CLAUDE_RUNNER_EXPECTED = f"claude -p --thinking enabled --effort low {PROMPT}\n"
CLAUDE_RUNNER_NO_PERSIST_EXPECTED = f"claude -p --thinking enabled --effort low --no-session-persistence {PROMPT}\n"
KIMI_RUNNER_EXPECTED = f"kimi --thinking --prompt {PROMPT}\n"
OPENCODE_PERSISTENCE_WARNING = 'warning: runner "opencode" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n'
KIMI_PERSISTENCE_WARNING = 'warning: runner "kimi" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n'
CRUSH_PERSISTENCE_WARNING = 'warning: runner "crush" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n'
ROOCODE_PERSISTENCE_WARNING = 'warning: runner "roocode" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n'
CURSOR_PERSISTENCE_WARNING = 'warning: runner "cursor" may save this session; pass --save-session to allow this explicitly or --cleanup-session to try cleanup\n'
HELP_USAGE_LINE = 'ccc [controls...] "<Prompt>"'
HELP_SLOT_LINE = (
    "Use a named preset from config; if no preset exists, runner names select runners before agent fallback"
)
HELP_PRINT_CONFIG_SNIPPET = "--print-config"
HELP_CONFIG_COMMAND_SNIPPET = "ccc config"
HELP_MIXED_HELP_SNIPPET = "--help / -h"
HELP_PRESET_PROMPT_LINE = "Presets can also define a default prompt"
HELP_PROMPT_MODE_LINE = "prompt_mode lets alias prompts prepend or append text"
HELP_EXHAUSTIVE_EXAMPLE_1 = (
    'ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"'
)
HELP_EXHAUSTIVE_EXAMPLE_2 = 'ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"'
HELP_PROJECT_LOCAL_CONFIG_LINE = ".ccc.toml (searched upward from CWD)"
HELP_GLOBAL_CONFIG_LINE = "XDG_CONFIG_HOME/ccc/config.toml"
HELP_HOME_CONFIG_LINE = "~/.config/ccc/config.toml"
HELP_SHOW_THINKING_SNIPPET = "--show-thinking"
HELP_SANITIZE_OSC_SNIPPET = "--sanitize-osc / --no-sanitize-osc"
HELP_OUTPUT_MODE_SNIPPET = (
    "--output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted>"
)
HELP_OUTPUT_SUGAR_SNIPPET = ".text / ..text, .json / ..json, .fmt / ..fmt"
HELP_COLOR_ENV_SNIPPET = "FORCE_COLOR / NO_COLOR"
HELP_PERMISSION_MODE_SNIPPET = "--permission-mode <safe|auto|yolo|plan>"
HELP_YOLO_SNIPPET = "--yolo / -y"
HELP_SAVE_SESSION_SNIPPET = "--save-session"
HELP_CLEANUP_SESSION_SNIPPET = "--cleanup-session"
HELP_DELIMITER_SNIPPET = "Treat all remaining args as prompt text"
SHOW_THINKING_IMPLEMENTATIONS = {"Python", "Rust"}
YOLO_IMPLEMENTATIONS = {"Python", "Rust"}
PROMPT_PRESET_IMPLEMENTATIONS = {"Python", "Rust"}
PRINT_CONFIG_IMPLEMENTATIONS = {"Python", "Rust"}
CONFIG_COMMAND_IMPLEMENTATIONS = {"Python", "Rust"}
ADD_ALIAS_IMPLEMENTATIONS = {"Python", "Rust"}
EXAMPLE_CONFIG_EXPECTED = (
    ROOT / "tests" / "fixtures" / "config-example.toml"
).read_text(encoding="utf-8")
PROJECT_LOCAL_CONFIG_IMPLEMENTATIONS = {"Python", "Rust"}
PROMPT_MODE_IMPLEMENTATIONS = {"Python", "Rust"}


class SingleImplCccContractTests(unittest.TestCase):
    selected_languages: List[LanguageSpec] = []

    @classmethod
    def setUpClass(cls) -> None:
        cls.build_env = os.environ.copy()
        cls.build_env["LC_ALL"] = "C"
        cls.build_env["PERL_BADLANG"] = "0"
        for lang in cls.selected_languages:
            lang.build(cls.build_env)
            if not lang.build_ok:
                raise RuntimeError(lang.build_error)

    def _make_env(self, opencode_path: Path, lang: LanguageSpec) -> Dict[str, str]:
        env = os.environ.copy()
        env["LC_ALL"] = "C"
        env["PERL_BADLANG"] = "0"
        env.update(lang.env_extra)
        env["PATH"] = f"{opencode_path.parent}:{env.get('PATH', '')}"
        config_root = opencode_path.parent.parent
        env["XDG_CONFIG_HOME"] = str(config_root / "xdg")
        env["XDG_CACHE_HOME"] = str(config_root / "xdg-cache")
        env["XDG_DATA_HOME"] = str(config_root / "xdg-data")
        env["XDG_STATE_HOME"] = str(config_root / "xdg-state")
        env["CCC_CONFIG"] = str(config_root / "missing-config.toml")
        env["HOME"] = str(config_root / "home")
        env["DOTNET_NOLOGO"] = "1"
        env["DOTNET_SKIP_FIRST_TIME_EXPERIENCE"] = "1"
        env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        for key in (
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
        ):
            Path(env[key]).mkdir(parents=True, exist_ok=True)
        home_config_path = Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
        home_config_path.parent.mkdir(parents=True, exist_ok=True)
        if not home_config_path.exists():
            home_config_path.write_text("", encoding="utf-8")
        config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        if not config_path.exists():
            config_path.write_text("", encoding="utf-8")
        if lang.name in {"x86-64 ASM", "OCaml"}:
            env["CCC_REAL_OPENCODE"] = str(opencode_path)
        return env

    def _run_with_prompt_assertion(self, prompt: str, assertion) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, prompt=prompt):
                    result = lang.invoke(prompt, self._make_env(opencode_path, lang))
                    assertion(result)

    def _run_with_configured_runner_assertion(self, assertion) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            claude_path = bin_dir / "claude"
            self._write_opencode_stub(opencode_path)
            self._write_runner_stub(claude_path, "claude")
            self._write_config(tmp_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, config="default_runner=claude"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path)
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    env["CCC_CONFIG"] = str(tmp_path / "legacy-config")
                    env.pop("CCC_REAL_OPENCODE", None)
                    if lang.name == "x86-64 ASM":
                        asm_config_path = tmp_path / "asm-config"
                        asm_config_path.write_text(f"default_runner = {claude_path}\n")
                        env["CCC_CONFIG"] = str(asm_config_path)
                    elif lang.name == "OCaml":
                        env["CCC_REAL_OPENCODE"] = str(claude_path)
                    result = lang.invoke(PROMPT, env)
                    assertion(result)

    def _run_with_extra_args_assertion(self, extra_args: List[str], assertion) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, extra_args=extra_args):
                    result = lang.invoke_extra(
                        extra_args, self._make_env(opencode_path, lang)
                    )
                    assertion(result)

    def _run_with_agent_stub_extra_args_assertion(
        self, extra_args: List[str], assertion
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_agent_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, extra_args=extra_args):
                    result = lang.invoke_extra(
                        extra_args, self._make_env(opencode_path, lang)
                    )
                    assertion(result)

    def _run_with_agent_preset_assertion(self, assertion) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_agent_opencode_stub(opencode_path)
            self._write_agent_preset_config(tmp_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, config="preset_agent"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path)
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    env["CCC_CONFIG"] = str(tmp_path / "legacy-config")
                    result = lang.invoke_extra(["@reviewer", PROMPT], env)
                    assertion(result)

    def _run_with_prompt_preset_assertion(self, prompt: str | None, assertion) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)
            self._write_prompt_preset_config(tmp_path)

            for lang in self.selected_languages:
                if lang.name not in PROMPT_PRESET_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, config="preset_prompt"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path)
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    env["CCC_CONFIG"] = str(tmp_path / "legacy-config")
                    if prompt is None:
                        result = lang.invoke_extra(["@commit"], env)
                    else:
                        result = lang.invoke_with_args(["@commit"], prompt, env)
                    assertion(result)

    def _run_with_prompt_mode_assertion(
        self, mode: str, prompt: str | None, assertion
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)
            self._write_prompt_mode_config(tmp_path, mode)

            for lang in self.selected_languages:
                if lang.name not in PROMPT_MODE_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, config=f"prompt_mode:{mode}"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path)
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    env["CCC_CONFIG"] = str(tmp_path / "legacy-config")
                    if prompt is None:
                        result = lang.invoke_extra(["@add-task"], env)
                    else:
                        result = lang.invoke_with_args(["@add-task"], prompt, env)
                    assertion(result)

    def _write_project_local_config(self, tmp_path: Path) -> Path:
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

        home_config_dir = tmp_path / ".config" / "ccc"
        xdg_config_dir = tmp_path / "xdg" / "ccc"
        home_config_dir.mkdir(parents=True)
        xdg_config_dir.mkdir(parents=True)
        (home_config_dir / "config.toml").write_text(
            '[defaults]\nrunner = "k"\n[aliases.review]\nshow_thinking = true\n'
        )
        (xdg_config_dir / "config.toml").write_text(
            '[defaults]\nmodel = "xdg-model"\n[aliases.review]\nmodel = "xdg-model"\n'
        )

        return nested_cwd

    def test_happy_path(self) -> None:
        self._run_with_prompt_assertion(PROMPT, self.assert_equal_output)

    def test_rejects_empty_prompt(self) -> None:
        self._run_with_prompt_assertion("", self.assert_rejects_empty)

    def test_requires_one_prompt_argument(self) -> None:
        self._run_with_extra_args_assertion([], self.assert_rejects_missing_prompt)

    def test_rejects_whitespace_only_prompt(self) -> None:
        self._run_with_prompt_assertion("   ", self.assert_rejects_empty)

    def test_prompt_only_uses_configured_default_runner(self) -> None:
        self._run_with_configured_runner_assertion(
            self.assert_uses_configured_default_runner
        )

    def test_env_override_can_replace_claude_binary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            claude_path = bin_dir / "claude-mock"
            self._write_opencode_stub(opencode_path)
            self._write_runner_stub(claude_path, "claude")

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, env="CCC_REAL_CLAUDE"):
                    env = self._make_env(opencode_path, lang)
                    env["CCC_REAL_CLAUDE"] = str(claude_path)
                    result = lang.invoke_extra(["cc", PROMPT], env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(
                        result.stdout,
                        {CLAUDE_RUNNER_EXPECTED, CLAUDE_RUNNER_NO_PERSIST_EXPECTED},
                    )
                    self.assertEqual(result.stderr, "")

    def test_env_override_can_replace_kimi_binary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            kimi_path = bin_dir / "kimi-mock"
            self._write_opencode_stub(opencode_path)
            self._write_runner_stub(kimi_path, "kimi")

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, env="CCC_REAL_KIMI"):
                    env = self._make_env(opencode_path, lang)
                    env["CCC_REAL_KIMI"] = str(kimi_path)
                    result = lang.invoke_extra(["k", PROMPT], env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, KIMI_RUNNER_EXPECTED)
                    self.assertIn(result.stderr, {"", KIMI_PERSISTENCE_WARNING})

    def test_env_override_can_replace_cursor_binary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            cursor_path = bin_dir / "cursor-mock"
            self._write_opencode_stub(opencode_path)
            self._write_runner_stub(cursor_path, "cursor-agent")

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                with self.subTest(language=lang.name, env="CCC_REAL_CURSOR"):
                    env = self._make_env(opencode_path, lang)
                    env["CCC_REAL_CURSOR"] = str(cursor_path)
                    result = lang.invoke_extra(["cu", "--save-session", PROMPT], env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        result.stdout,
                        "cursor-agent --print --trust Fix the failing tests\n",
                    )
                    self.assertEqual(result.stderr, "")

    def test_name_without_preset_falls_back_to_agent(self) -> None:
        self._run_with_agent_stub_extra_args_assertion(
            ["@reviewer", PROMPT], self.assert_uses_agent_fallback
        )

    def test_name_matching_runner_selector_uses_runner_not_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            kimi_path = bin_dir / "kimi"
            self._write_opencode_stub(opencode_path)
            self._write_structured_argv_echo_stub(kimi_path, "kimi", "kimi")

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                config_path.write_text(
                    '[defaults]\nrunner = "k"\noutput_mode = "stream-formatted"\n',
                    encoding="utf-8",
                )
                with self.subTest(language=lang.name):
                    result = lang.invoke_extra(["@k", PROMPT], env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        result.stdout,
                        "[assistant] kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    )
                    self.assertEqual(result.stderr, KIMI_PERSISTENCE_WARNING)

    def test_preset_named_like_runner_selector_wins(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                config_path.write_text(
                    '[aliases.k]\nagent = "specialist"\n',
                    encoding="utf-8",
                )
                with self.subTest(language=lang.name):
                    result = lang.invoke_extra(["@k", PROMPT], env)
                    self.assert_uses_preset_agent(result)

    def test_preset_agent_wins_over_name_fallback(self) -> None:
        self._run_with_agent_preset_assertion(self.assert_uses_preset_agent)

    def test_preset_prompt_fills_missing_prompt(self) -> None:
        self._run_with_prompt_preset_assertion(None, self.assert_uses_preset_prompt)

    def test_explicit_prompt_overrides_preset_prompt(self) -> None:
        self._run_with_prompt_preset_assertion(PROMPT, self.assert_equal_output)

    def test_whitespace_prompt_falls_back_to_preset_prompt(self) -> None:
        self._run_with_prompt_preset_assertion("   ", self.assert_uses_preset_prompt)

    def test_prompt_mode_prepend_composes_alias_prompt(self) -> None:
        self._run_with_prompt_mode_assertion(
            "prepend",
            "a new feature",
            self.assert_uses_prepend_prompt_mode,
        )

    def test_prompt_mode_append_composes_alias_prompt(self) -> None:
        self._run_with_prompt_mode_assertion(
            "append",
            "a new feature",
            self.assert_uses_append_prompt_mode,
        )

    def test_prompt_mode_allows_explicit_empty_prompt(self) -> None:
        self._run_with_prompt_mode_assertion(
            "prepend",
            "",
            self.assert_uses_prompt_mode_with_explicit_empty_prompt,
        )

    def test_prompt_mode_requires_explicit_prompt_argument(self) -> None:
        self._run_with_prompt_mode_assertion(
            "prepend",
            None,
            self.assert_rejects_missing_prompt_mode_argument,
        )

    def test_help_surface_mentions_standard_name_slot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_standard_name_slot(
                        result, HELP_USAGE_LINE
                    )

    def test_help_surface_reads_opencode_package_metadata_when_version_command_fails(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            package_root = tmp_path / "node_modules" / "opencode-ai"
            package_bin = package_root / "bin"
            package_bin.mkdir(parents=True)
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            opencode_path.symlink_to(package_bin / "opencode")
            (package_root / "package.json").write_text(
                '{"name":"opencode-ai","version":"1.3.17"}',
                encoding="utf-8",
            )
            (package_bin / "opencode").write_text(
                "#!/bin/sh\n"
                'if [ "$1" = "--version" ]; then\n'
                "  exit 99\n"
                "fi\n"
                'if [ "$1" != "run" ]; then\n'
                "  exit 9\n"
                "fi\n"
                "shift\n"
                "printf 'opencode run %s\\n' \"$*\"\n",
                encoding="utf-8",
            )
            (package_bin / "opencode").chmod(
                (package_bin / "opencode").stat().st_mode
                | stat.S_IXUSR
                | stat.S_IXGRP
                | stat.S_IXOTH
            )

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("[+] opencode", result.stdout)
                    self.assertIn("1.3.17", result.stdout)

    def test_help_surface_mentions_show_thinking_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in SHOW_THINKING_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_show_thinking_flag(result)

    def test_help_surface_mentions_print_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in PRINT_CONFIG_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_print_config(result)

    def test_help_wins_when_mixed_with_other_args(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            cases = [
                ["@reviewer", "--help"],
                [PROMPT, "--help"],
                ["--", "--help"],
            ]

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                for extra_args in cases:
                    with self.subTest(language=lang.name, extra_args=extra_args):
                        result = lang.invoke_extra(extra_args, env)
                        self.assert_help_mentions_standard_name_slot(
                            result, HELP_USAGE_LINE
                        )

    def test_help_surface_mentions_sanitize_osc_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in SHOW_THINKING_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_sanitize_osc_flag(result)

    def test_help_surface_mentions_output_modes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in SHOW_THINKING_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_output_modes(result)

    def test_help_surface_mentions_color_envs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_color_envs(result)

    def test_help_surface_mentions_yolo_and_delimiter(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in YOLO_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_yolo_and_delimiter(result)

    def test_help_surface_mentions_preset_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in PROMPT_PRESET_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assert_help_mentions_preset_prompt(result)

    def test_print_config_outputs_example_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in PRINT_CONFIG_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--print-config"]):
                    result = lang.invoke_extra(
                        ["--print-config"], self._make_env(opencode_path, lang)
                    )
                    self.assert_print_config_output(result)

    def test_config_command_outputs_resolved_default_config(self) -> None:
        config_body = '[defaults]\nrunner = "cc"\n'
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in CONFIG_COMMAND_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, command="config"):
                    env = self._make_env(opencode_path, lang)
                    env.pop("CCC_CONFIG", None)
                    env["HOME"] = str(tmp_path / "home")
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    home_config_path = (
                        Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
                    )
                    config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    config_path.parent.mkdir(parents=True, exist_ok=True)
                    config_path.write_text(config_body, encoding="utf-8")
                    result = lang.invoke_extra(["config"], env)
                    self.assert_config_command_outputs_paths(
                        result,
                        [
                            (home_config_path, ""),
                            (config_path, config_body),
                        ],
                    )

    def test_config_command_outputs_all_default_config_paths(self) -> None:
        home_body = '[defaults]\nrunner = "cc"\n'
        xdg_body = '[defaults]\nmodel = "xdg-model"\n'
        project_body = '[aliases.review]\nprompt = "Review"\n'
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in CONFIG_COMMAND_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, command="config-all-paths"):
                    env = self._make_env(opencode_path, lang)
                    env.pop("CCC_CONFIG", None)
                    env["HOME"] = str(tmp_path / "home")
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    repo_path = tmp_path / f"repo-{lang.name}"
                    nested_cwd = repo_path / "nested"
                    nested_cwd.mkdir(parents=True)

                    home_path = (
                        Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
                    )
                    xdg_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    project_path = repo_path / ".ccc.toml"
                    home_path.parent.mkdir(parents=True, exist_ok=True)
                    xdg_path.parent.mkdir(parents=True, exist_ok=True)
                    home_path.write_text(home_body, encoding="utf-8")
                    xdg_path.write_text(xdg_body, encoding="utf-8")
                    project_path.write_text(project_body, encoding="utf-8")

                    result = lang.invoke_extra(["config"], env, cwd=nested_cwd)
                    self.assert_config_command_outputs_paths(
                        result,
                        [
                            (home_path, home_body),
                            (xdg_path, xdg_body),
                            (project_path, project_body),
                        ],
                    )

    def test_config_command_prefers_ccc_config_override(self) -> None:
        fallback_body = '[defaults]\nrunner = "k"\n'
        override_body = '[defaults]\nrunner = "cc"\n'
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in CONFIG_COMMAND_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, command="config-override"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path / "home")
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    fallback_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    fallback_path.parent.mkdir(parents=True, exist_ok=True)
                    fallback_path.write_text(fallback_body, encoding="utf-8")
                    override_path = tmp_path / "custom-config.toml"
                    override_path.write_text(override_body, encoding="utf-8")
                    env["CCC_CONFIG"] = str(override_path)
                    result = lang.invoke_extra(["config"], env)
                    self.assert_config_command_output(
                        result, override_path, override_body
                    )

    def test_config_command_falls_back_when_ccc_config_is_missing(self) -> None:
        fallback_body = '[defaults]\nrunner = "k"\n'
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in CONFIG_COMMAND_IMPLEMENTATIONS:
                    continue
                with self.subTest(
                    language=lang.name, command="config-missing-override"
                ):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path / "home")
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    fallback_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    home_config_path = (
                        Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
                    )
                    fallback_path.parent.mkdir(parents=True, exist_ok=True)
                    fallback_path.write_text(fallback_body, encoding="utf-8")
                    env["CCC_CONFIG"] = str(tmp_path / "missing-config.toml")
                    result = lang.invoke_extra(["config"], env)
                    self.assert_config_command_outputs_paths(
                        result,
                        [
                            (home_config_path, ""),
                            (fallback_path, fallback_body),
                        ],
                    )

    def test_config_command_reports_missing_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in CONFIG_COMMAND_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, command="config-missing"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path / "home")
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    env["CCC_CONFIG"] = str(tmp_path / "missing-config.toml")
                    home_config_path = (
                        Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
                    )
                    xdg_config_path = (
                        Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    )
                    for existing in (home_config_path, xdg_config_path):
                        if existing.exists():
                            existing.unlink()
                    result = lang.invoke_extra(["config"], env)
                    self.assert_missing_config_command(result, env["CCC_CONFIG"])

    def test_add_alias_yes_writes_config_and_alias_is_usable(self) -> None:
        alias_block = (
            "[aliases.mm27]\n"
            'runner = "oc"\n'
            'prompt = "Fix the failing tests"\n'
            'prompt_mode = "default"\n'
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in ADD_ALIAS_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, command="add-alias"):
                    env = self._make_env(opencode_path, lang)
                    add_result = lang.invoke_extra(
                        [
                            "add",
                            "mm27",
                            "--runner",
                            "oc",
                            "--prompt",
                            "Fix the failing tests",
                            "--prompt-mode",
                            "default",
                            "--yes",
                        ],
                        env,
                    )
                    config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                    self.assertEqual(add_result.returncode, 0, add_result.stderr)
                    self.assertIn(f"Config path: {config_path}", add_result.stdout)
                    self.assertIn("Alias @mm27 written", add_result.stdout)
                    self.assertEqual(
                        config_path.read_text(encoding="utf-8"), alias_block
                    )

                    config_result = lang.invoke_extra(["config"], env)
                    home_config_path = (
                        Path(env["HOME"]) / ".config" / "ccc" / "config.toml"
                    )
                    self.assert_config_command_outputs_paths(
                        config_result,
                        [
                            (home_config_path, ""),
                            (config_path, alias_block),
                        ],
                    )

                    alias_result = lang.invoke_extra(["@mm27"], env)
                    self.assert_equal_output(alias_result)

    def test_help_surface_mentions_project_local_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in PROJECT_LOCAL_CONFIG_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, extra_args=["--help"]):
                    result = lang.invoke_extra(
                        ["--help"], self._make_env(opencode_path, lang)
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(HELP_PROJECT_LOCAL_CONFIG_LINE, result.stdout)
                    self.assertIn(HELP_GLOBAL_CONFIG_LINE, result.stdout)
                    self.assertIn(HELP_HOME_CONFIG_LINE, result.stdout)

    def test_project_local_config_layers_over_global_configs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            kimi_path = bin_dir / "kimi"
            self._write_opencode_stub(opencode_path)
            self._write_runner_stub(kimi_path, "kimi")
            nested_cwd = self._write_project_local_config(tmp_path)

            for lang in self.selected_languages:
                if lang.name not in PROJECT_LOCAL_CONFIG_IMPLEMENTATIONS:
                    continue
                with self.subTest(language=lang.name, config="project-local"):
                    env = self._make_env(opencode_path, lang)
                    env["HOME"] = str(tmp_path)
                    env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                    result = lang.invoke_extra(["@review"], env, cwd=nested_cwd)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, PROJECT_LOCAL_PROMPT_EXPECTED)
                    self.assertIn(result.stderr, {"", KIMI_PERSISTENCE_WARNING})

    def test_permission_mode_maps_to_runner_specific_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            codex_path = bin_dir / "codex"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            roocode_path = bin_dir / "roocode"
            cursor_path = bin_dir / "cursor-agent"
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(codex_path, "codex")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_opencode_yolo_stub(opencode_path)
            self._write_argv_echo_stub(roocode_path, "roocode")
            self._write_argv_echo_stub(cursor_path, "cursor-agent")

            cases = {
                "Python": [
                    (
                        ["cc", "--permission-mode", "safe"],
                        "claude -p --thinking enabled --effort low --permission-mode default --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["oc", "--permission-mode", "safe"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                        f'{OPENCODE_PERSISTENCE_WARNING}{{"permission":"ask"}}',
                    ),
                    (
                        ["rc", "--permission-mode", "safe"],
                        "roocode Fix the failing tests\n",
                        'warning: runner "roocode" safe mode is unverified; leaving default permissions unchanged\n'
                        + ROOCODE_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cc", "--permission-mode", "auto"],
                        "claude -p --thinking enabled --effort low --permission-mode auto --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["c", "--permission-mode", "auto"],
                        "codex exec --full-auto --ephemeral Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["cc", "--permission-mode", "plan"],
                        "claude -p --thinking enabled --effort low --permission-mode plan --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["k", "--permission-mode", "plan"],
                        "kimi --thinking --plan --prompt Fix the failing tests\n",
                        KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["k", "--permission-mode", "auto"],
                        "kimi --thinking --prompt Fix the failing tests\n",
                        'warning: runner "k" does not support permission mode "auto"; ignoring it\n'
                        + KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cu", "--permission-mode", "safe"],
                        "cursor-agent --print --trust --sandbox enabled Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cursor", "--permission-mode", "plan"],
                        "cursor-agent --print --trust --mode plan Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cu", "--permission-mode", "auto"],
                        "cursor-agent --print --trust Fix the failing tests\n",
                        'warning: runner "cu" does not support permission mode "auto"; ignoring it\n'
                        + CURSOR_PERSISTENCE_WARNING,
                    ),
                ],
                "Rust": [
                    (
                        ["cc", "--permission-mode", "safe"],
                        "claude -p --thinking enabled --effort low --permission-mode default --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["oc", "--permission-mode", "safe"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                        f'{OPENCODE_PERSISTENCE_WARNING}{{"permission":"ask"}}',
                    ),
                    (
                        ["rc", "--permission-mode", "safe"],
                        "roocode Fix the failing tests\n",
                        'warning: runner "roocode" safe mode is unverified; leaving default permissions unchanged\n'
                        + ROOCODE_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cc", "--permission-mode", "auto"],
                        "claude -p --thinking enabled --effort low --permission-mode auto --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["c", "--permission-mode", "auto"],
                        "codex exec --full-auto --ephemeral Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["cc", "--permission-mode", "plan"],
                        "claude -p --thinking enabled --effort low --permission-mode plan --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["k", "--permission-mode", "plan"],
                        "kimi --thinking --plan --prompt Fix the failing tests\n",
                        KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["k", "--permission-mode", "auto"],
                        "kimi --thinking --prompt Fix the failing tests\n",
                        'warning: runner "k" does not support permission mode "auto"; ignoring it\n'
                        + KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cu", "--permission-mode", "safe"],
                        "cursor-agent --print --trust --sandbox enabled Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cursor", "--permission-mode", "plan"],
                        "cursor-agent --print --trust --mode plan Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cu", "--permission-mode", "auto"],
                        "cursor-agent --print --trust Fix the failing tests\n",
                        'warning: runner "cu" does not support permission mode "auto"; ignoring it\n'
                        + CURSOR_PERSISTENCE_WARNING,
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="permission-mode"):
                    for extra_args, expected_stdout, expected_stderr in cases[
                        lang.name
                    ]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertIn(result.stderr, {expected_stderr, expected_stderr + "\n"})

    def test_codex_runner_uses_exec_subcommand(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            codex_path = bin_dir / "codex"
            self._write_opencode_stub(opencode_path)
            self._write_codex_stub(codex_path)

            for lang in self.selected_languages:
                with self.subTest(language=lang.name, runner="codex"):
                    if lang.name in {"x86-64 ASM", "OCaml"}:
                        continue
                    env = self._make_env(opencode_path, lang)
                    result = lang.invoke_extra(["c", PROMPT], env)
                    self.assert_uses_codex_exec_runner(result)

    def test_show_thinking_flag_sets_runner_capability(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            self._write_argv_echo_stub(opencode_path, "opencode")
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(kimi_path, "kimi")

            cases = {
                "Python": [
                    (["--show-thinking"], None),
                    (
                        ["cc", "--show-thinking"],
                        "claude -p --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", "--show-thinking"],
                        "kimi --thinking --prompt Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (["--show-thinking"], None),
                    (
                        ["cc", "--show-thinking"],
                        "claude -p --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", "--show-thinking"],
                        "kimi --thinking --prompt Fix the failing tests\n",
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                env["HOME"] = str(tmp_path)
                env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
                env["CCC_CONFIG"] = str(tmp_path / "config.toml")
                with self.subTest(language=lang.name, capability="show-thinking"):
                    for extra_args, expected_stdout in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            local_env = env.copy()
                            if extra_args == ["--show-thinking"]:
                                local_env["CCC_REAL_OPENCODE"] = str(
                                    ROOT
                                    / "tests"
                                    / "mock-coding-cli"
                                    / "mock_coding_cli.sh"
                                )
                                local_env["MOCK_JSON_SCHEMA"] = "opencode"
                            prompt = "tool call" if expected_stdout is None else PROMPT
                            result = lang.invoke_with_args(
                                extra_args, prompt, local_env
                            )
                            self.assertEqual(result.returncode, 0, result.stderr)
                            if expected_stdout is None:
                                self.assertIn("tool call executed", result.stdout)
                                self.assertIn("read", result.stdout)
                            else:
                                self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(
                                result.stderr,
                                self._expected_persistence_warning_for_args(extra_args),
                            )

    def test_thinking_levels_map_to_claude_effort_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            opencode_path = bin_dir / "opencode"
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_opencode_stub(opencode_path)

            cases = {
                "Python": [
                    (
                        ["cc", "+3"],
                        "claude -p --thinking enabled --effort high --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "+4"],
                        "claude -p --thinking enabled --effort max --no-session-persistence Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (
                        ["cc", "+3"],
                        "claude -p --thinking enabled --effort high --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "+4"],
                        "claude -p --thinking enabled --effort max --no-session-persistence Fix the failing tests\n",
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="thinking-levels"):
                    for extra_args, expected_stdout in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(result.stderr, "")

    def test_output_mode_maps_to_runner_specific_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            cursor_path = bin_dir / "cursor-agent"
            codex_path = bin_dir / "codex"
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_argv_echo_stub(opencode_path, "opencode")
            self._write_argv_echo_stub(cursor_path, "cursor-agent")
            self._write_argv_echo_stub(codex_path, "codex")

            cases = {
                "Python": [
                    (
                        ["cc", ".json"],
                        "claude -p --output-format json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "..json"],
                        "claude -p --verbose --output-format stream-json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", "..json"],
                        "kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["oc", ".json"],
                        "opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["c", ".json"],
                        "codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["codex", "..json"],
                        "codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["cu", ".json"],
                        "cursor-agent --print --trust --output-format json Fix the failing tests\n",
                    ),
                    (
                        ["cursor", "..json"],
                        "cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (
                        ["cc", ".json"],
                        "claude -p --output-format json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "..json"],
                        "claude -p --verbose --output-format stream-json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", "..json"],
                        "kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["oc", ".json"],
                        "opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["c", ".json"],
                        "codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["codex", "..json"],
                        "codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["cu", ".json"],
                        "cursor-agent --print --trust --output-format json Fix the failing tests\n",
                    ),
                    (
                        ["cursor", "..json"],
                        "cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="output-mode"):
                    for extra_args, expected_stdout in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(
                                result.stderr,
                                self._expected_persistence_warning_for_args(extra_args),
                            )

    def test_formatted_output_mode_sugar_renders_structured_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            cursor_path = bin_dir / "cursor-agent"
            codex_path = bin_dir / "codex"
            self._write_structured_argv_echo_stub(claude_path, "claude", "claude-code")
            self._write_structured_argv_echo_stub(kimi_path, "kimi", "kimi")
            self._write_structured_argv_echo_stub(opencode_path, "opencode", "opencode")
            self._write_structured_argv_echo_stub(
                cursor_path, "cursor-agent", "cursor-agent"
            )
            self._write_structured_argv_echo_stub(codex_path, "codex", "codex")

            cases = {
                "Python": [
                    (
                        ["cc", ".fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "..fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --include-partial-messages --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", ".fmt"],
                        "[assistant] kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["k", "..fmt"],
                        "[assistant] kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["oc", ".fmt"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["oc", "..fmt"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["c", ".fmt"],
                        "[assistant] codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["codex", "..fmt"],
                        "[assistant] codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["cu", ".fmt"],
                        "[assistant] cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                    (
                        ["cursor", "..fmt"],
                        "[assistant] cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (
                        ["cc", ".fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["cc", "..fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --include-partial-messages --thinking enabled --effort low --no-session-persistence Fix the failing tests\n",
                    ),
                    (
                        ["k", ".fmt"],
                        "[assistant] kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["k", "..fmt"],
                        "[assistant] kimi --print --output-format stream-json --thinking --prompt Fix the failing tests\n",
                    ),
                    (
                        ["oc", ".fmt"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["oc", "..fmt"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                    ),
                    (
                        ["c", ".fmt"],
                        "[assistant] codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["codex", "..fmt"],
                        "[assistant] codex exec --json --ephemeral Fix the failing tests\n",
                    ),
                    (
                        ["cu", ".fmt"],
                        "[assistant] cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                    (
                        ["cursor", "..fmt"],
                        "[assistant] cursor-agent --print --trust --output-format stream-json Fix the failing tests\n",
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(
                    language=lang.name, capability="formatted-output-mode"
                ):
                    for extra_args, expected_stdout in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(
                                result.stderr,
                                self._expected_persistence_warning_for_args(extra_args),
                            )

    def test_force_color_env_overrides_no_color_in_formatted_modes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_structured_argv_echo_stub(opencode_path, "opencode", "opencode")

            expected_stdout = (
                "\x1b[96m💬\x1b[0m opencode run --format json --thinking Fix the failing tests\n"
            )

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                env["FORCE_COLOR"] = "1"
                env["NO_COLOR"] = "1"
                with self.subTest(language=lang.name, capability="force-color"):
                    result = lang.invoke_with_args(["oc", ".fmt"], PROMPT, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, expected_stdout)
                    self.assertEqual(result.stderr, OPENCODE_PERSISTENCE_WARNING)

    def test_unsupported_output_mode_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            roocode_path = bin_dir / "roocode"
            self._write_argv_echo_stub(roocode_path, "roocode")

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(bin_dir / "opencode", lang)
                with self.subTest(language=lang.name):
                    result = lang.invoke_with_args(["rc", "..json"], PROMPT, env)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("output mode", result.stderr)

    def test_configured_unsupported_output_mode_warns_and_falls_back(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            roocode_path = bin_dir / "roocode"
            self._write_opencode_stub(opencode_path)
            self._write_argv_echo_stub(roocode_path, "roocode")
            expected_warning = (
                'warning: runner "roocode" does not support configured output mode '
                '"stream-formatted"; falling back to "text"\n'
                + ROOCODE_PERSISTENCE_WARNING
            )

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                config_path.write_text(
                    '[defaults]\noutput_mode = "stream-formatted"\n',
                    encoding="utf-8",
                )
                with self.subTest(language=lang.name):
                    result = lang.invoke_with_args(["rc"], PROMPT, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, f"roocode {PROMPT}\n")
                    self.assertEqual(result.stderr, expected_warning)

    def test_alias_unsupported_output_mode_warns_and_falls_back(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            roocode_path = bin_dir / "roocode"
            self._write_opencode_stub(opencode_path)
            self._write_argv_echo_stub(roocode_path, "roocode")
            expected_warning = (
                'warning: runner "roocode" does not support alias output mode '
                '"stream-formatted"; falling back to "text"\n'
                + ROOCODE_PERSISTENCE_WARNING
            )

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                config_path = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
                config_path.write_text(
                    '[aliases.fast]\nrunner = "rc"\noutput_mode = "stream-formatted"\n',
                    encoding="utf-8",
                )
                with self.subTest(language=lang.name):
                    result = lang.invoke_with_args(["@fast"], PROMPT, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, f"roocode {PROMPT}\n")
                    self.assertEqual(result.stderr, expected_warning)

    def test_control_tokens_are_order_independent_before_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            kimi_path = bin_dir / "kimi"
            self._write_argv_echo_stub(kimi_path, "kimi")

            for lang in self.selected_languages:
                if lang.name not in YOLO_IMPLEMENTATIONS:
                    continue
                env = self._make_env(bin_dir / "opencode", lang)
                with self.subTest(language=lang.name):
                    result = lang.invoke_with_args(
                        ["@reviewer", "--yolo", ":moonshot:k2", "k", "+4"],
                        PROMPT,
                        env,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        result.stdout,
                        "kimi --thinking --model k2 --agent reviewer --yolo --prompt Fix the failing tests\n",
                    )
                    self.assertEqual(result.stderr, KIMI_PERSISTENCE_WARNING)

    def test_double_dash_forces_literal_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_opencode_yolo_stub(opencode_path)

            for lang in self.selected_languages:
                if lang.name not in YOLO_IMPLEMENTATIONS:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name):
                    result = lang.invoke_extra(
                        ["-y", "--", "+1", "@agent", ":model"],
                        env,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        result.stdout,
                        "[assistant] opencode run --format json --thinking +1 @agent :model\n",
                    )
                    expected_stderr = f'{OPENCODE_PERSISTENCE_WARNING}{{"permission":"allow"}}'
                    self.assertIn(result.stderr, {expected_stderr, expected_stderr + "\n"})

    def test_yolo_maps_to_runner_specific_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            codex_path = bin_dir / "codex"
            kimi_path = bin_dir / "kimi"
            crush_path = bin_dir / "crush"
            opencode_path = bin_dir / "opencode"
            cursor_path = bin_dir / "cursor-agent"
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(codex_path, "codex")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_argv_echo_stub(crush_path, "crush")
            self._write_opencode_yolo_stub(opencode_path)
            self._write_argv_echo_stub(cursor_path, "cursor-agent")

            cases = {
                "Python": [
                    (
                        ["cc", "--yolo"],
                        "claude -p --thinking enabled --effort low --dangerously-skip-permissions --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["c", "--yolo"],
                        "codex exec --dangerously-bypass-approvals-and-sandbox --ephemeral Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["k", "-y"],
                        "kimi --thinking --yolo --prompt Fix the failing tests\n",
                        KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cr", "--yolo"],
                        "crush run Fix the failing tests\n",
                        'warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo\n'
                        + CRUSH_PERSISTENCE_WARNING,
                    ),
                    (
                        ["oc", "--yolo"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                        f'{OPENCODE_PERSISTENCE_WARNING}{{"permission":"allow"}}',
                    ),
                    (
                        ["cu", "--yolo"],
                        "cursor-agent --print --trust --yolo Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                ],
                "Rust": [
                    (
                        ["cc", "--yolo"],
                        "claude -p --thinking enabled --effort low --dangerously-skip-permissions --no-session-persistence Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["c", "--yolo"],
                        "codex exec --dangerously-bypass-approvals-and-sandbox --ephemeral Fix the failing tests\n",
                        "",
                    ),
                    (
                        ["k", "-y"],
                        "kimi --thinking --yolo --prompt Fix the failing tests\n",
                        KIMI_PERSISTENCE_WARNING,
                    ),
                    (
                        ["cr", "--yolo"],
                        "crush run Fix the failing tests\n",
                        'warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo\n'
                        + CRUSH_PERSISTENCE_WARNING,
                    ),
                    (
                        ["oc", "--yolo"],
                        "[assistant] opencode run --format json --thinking Fix the failing tests\n",
                        f'{OPENCODE_PERSISTENCE_WARNING}{{"permission":"allow"}}',
                    ),
                    (
                        ["cu", "--yolo"],
                        "cursor-agent --print --trust --yolo Fix the failing tests\n",
                        CURSOR_PERSISTENCE_WARNING,
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="yolo"):
                    for extra_args, expected_stdout, expected_stderr in cases[
                        lang.name
                    ]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertIn(result.stderr, {expected_stderr, expected_stderr + "\n"})

    def assert_equal_output(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, EXPECTED)
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_rejects_empty(self, result) -> None:
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertNotEqual(result.stderr, "")

    def assert_rejects_missing_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertNotEqual(result.stderr, "")
        self.assertTrue(
            'ccc "<Prompt>"' in result.stderr or "ccc" in result.stderr.lower(),
            f"Expected usage message in stderr, got: {result.stderr!r}",
        )
        self.assertIn(HELP_USAGE_LINE, result.stderr)

    def assert_uses_configured_default_runner(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            result.stdout,
            {CONFIG_DEFAULT_RUNNER_EXPECTED, CLAUDE_RUNNER_NO_PERSIST_EXPECTED},
        )
        self.assertEqual(result.stderr, "")

    def assert_uses_agent_fallback(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, AGENT_FALLBACK_EXPECTED)
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_uses_preset_agent(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PRESET_AGENT_EXPECTED)
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_uses_preset_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PRESET_PROMPT_EXPECTED)
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_uses_prepend_prompt_mode(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "opencode run Add this task:\na new feature\n")
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_uses_append_prompt_mode(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "opencode run a new feature\nAdd this task:\n")
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_uses_prompt_mode_with_explicit_empty_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "opencode run Add this task:\n")
        self.assertIn(result.stderr, {"", OPENCODE_PERSISTENCE_WARNING})

    def assert_rejects_missing_prompt_mode_argument(self, result) -> None:
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn(
            "prompt_mode prepend requires an explicit prompt argument",
            result.stderr,
        )

    def assert_help_mentions_standard_name_slot(
        self, result, expected_usage_line
    ) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(expected_usage_line, result.stdout)
        self.assertIn(HELP_SLOT_LINE, result.stdout)
        self.assertIn(HELP_EXHAUSTIVE_EXAMPLE_1, result.stdout)
        self.assertIn(HELP_EXHAUSTIVE_EXAMPLE_2, result.stdout)

    def assert_help_mentions_show_thinking_flag(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        if any(lang.name in {"Python", "Rust"} for lang in self.selected_languages):
            self.assertIn(HELP_SHOW_THINKING_SNIPPET, result.stdout)
            self.assertIn("show_thinking", result.stdout)

    def assert_help_mentions_print_config(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_PRINT_CONFIG_SNIPPET, result.stdout)
        self.assertIn(HELP_CONFIG_COMMAND_SNIPPET, result.stdout)
        self.assertIn(HELP_MIXED_HELP_SNIPPET, result.stdout)

    def assert_help_mentions_sanitize_osc_flag(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_SANITIZE_OSC_SNIPPET, result.stdout)
        self.assertIn("sanitize_osc", result.stdout)

    def assert_help_mentions_output_modes(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_OUTPUT_MODE_SNIPPET, result.stdout)
        self.assertIn(HELP_OUTPUT_SUGAR_SNIPPET, result.stdout)

    def assert_help_mentions_color_envs(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_COLOR_ENV_SNIPPET, result.stdout)
        self.assertIn("FORCE_COLOR", result.stdout)
        self.assertIn("NO_COLOR", result.stdout)

    def assert_help_mentions_yolo_and_delimiter(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_PERMISSION_MODE_SNIPPET, result.stdout)
        self.assertIn(HELP_YOLO_SNIPPET, result.stdout)
        self.assertIn(HELP_SAVE_SESSION_SNIPPET, result.stdout)
        self.assertIn(HELP_CLEANUP_SESSION_SNIPPET, result.stdout)
        self.assertIn(HELP_DELIMITER_SNIPPET, result.stdout)

    def assert_help_mentions_preset_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_PRESET_PROMPT_LINE, result.stdout)
        self.assertIn(HELP_PROMPT_MODE_LINE, result.stdout)

    def assert_print_config_output(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, EXAMPLE_CONFIG_EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_config_command_output(
        self, result, config_path: Path, config_body: str
    ) -> None:
        self.assert_config_command_outputs_paths(result, [(config_path, config_body)])

    def assert_config_command_outputs_paths(
        self, result, path_bodies: list[tuple[Path, str]]
    ) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "\n".join(
                f"Config path: {config_path}\n{config_body}"
                for config_path, config_body in path_bodies
            ),
        )
        self.assertEqual(result.stderr, "")

    def assert_missing_config_command(self, result, missing_path: str) -> None:
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("No config file found", result.stderr)
        self.assertIn(missing_path, result.stderr)

    def assert_uses_codex_exec_runner(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            result.stdout, {CODEX_RUNNER_EXPECTED, CODEX_RUNNER_NO_PERSIST_EXPECTED}
        )
        self.assertEqual(result.stderr, "")

    def _expected_persistence_warning_for_args(self, extra_args: list[str]) -> str:
        if "k" in extra_args or "kimi" in extra_args:
            return KIMI_PERSISTENCE_WARNING
        if "oc" in extra_args or "opencode" in extra_args:
            return OPENCODE_PERSISTENCE_WARNING
        if "cr" in extra_args or "crush" in extra_args:
            return CRUSH_PERSISTENCE_WARNING
        if "rc" in extra_args or "roocode" in extra_args:
            return ROOCODE_PERSISTENCE_WARNING
        if "cu" in extra_args or "cursor" in extra_args:
            return CURSOR_PERSISTENCE_WARNING
        if (
            "cc" in extra_args
            or "claude" in extra_args
            or "c" in extra_args
            or "codex" in extra_args
        ):
            return ""
        return OPENCODE_PERSISTENCE_WARNING

    def _write_opencode_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "run" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
            'args="$*"\n'
            'if [ "$1" = "--format" ] && [ "${2:-}" = "json" ]; then\n'
            '  printf \'{"response":"opencode run %s"}\\n\' "$args"\n'
            "else\n"
            "  printf 'opencode run %s\\n' \"$args\"\n"
            "fi\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_runner_stub(self, path: Path, runner_name: str) -> None:
        path.write_text(f"#!/bin/sh\nprintf '{runner_name} %s\\n' \"$*\"\n")
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_argv_echo_stub(self, path: Path, runner_name: str) -> None:
        path.write_text(f"#!/bin/sh\nprintf '{runner_name} %s\\n' \"$*\"\n")
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_structured_argv_echo_stub(
        self, path: Path, runner_name: str, schema_name: str
    ) -> None:
        if schema_name == "claude-code":
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"type":"assistant","message":{{"content":[{{"type":"text","text":"{runner_name} %s"}}]}}}}\\n\' "$*"\n'
                f'printf \'{{"type":"result","subtype":"success","result":"{runner_name} %s"}}\\n\' "$*"\n'
            )
        elif schema_name == "kimi":
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"role":"assistant","content":"{runner_name} %s"}}\\n\' "$*"\n'
            )
        elif schema_name == "cursor-agent":
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"type":"system","subtype":"init","session_id":"mock-cursor"}}\\n\'\n'
                f'printf \'{{"type":"assistant","message":{{"content":[{{"type":"text","text":"{runner_name} %s"}}]}},"session_id":"mock-cursor"}}\\n\' "$*"\n'
                f'printf \'{{"type":"result","subtype":"success","result":"{runner_name} %s","session_id":"mock-cursor"}}\\n\' "$*"\n'
            )
        elif schema_name == "codex":
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"type":"thread.started","thread_id":"mock-codex"}}\\n\'\n'
                f'printf \'{{"type":"item.completed","item":{{"id":"item_0","type":"agent_message","text":"{runner_name} %s"}}}}\\n\' "$*"\n'
                f'printf \'{{"type":"turn.completed","usage":{{"input_tokens":1,"output_tokens":2}}}}\\n\'\n'
            )
        else:
            body = f'#!/bin/sh\nprintf \'{{"response":"{runner_name} %s"}}\\n\' "$*"\n'
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_codex_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "exec" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
            'if [ "$1" = "--ephemeral" ]; then\n'
            "  shift\n"
            "fi\n"
            "printf 'codex exec %s\\n' \"$1\"\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_opencode_yolo_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "run" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
            'args="$*"\n'
            'if [ "$1" = "--format" ] && [ "${2:-}" = "json" ]; then\n'
            '  printf \'{"response":"opencode run %s"}\\n\' "$args"\n'
            "else\n"
            "  printf 'opencode run %s\\n' \"$args\"\n"
            "fi\n"
            'if [ -n "$OPENCODE_CONFIG_CONTENT" ]; then\n'
            "  printf '%s' \"$OPENCODE_CONFIG_CONTENT\" >&2\n"
            "fi\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_agent_opencode_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "run" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
            'format=""\n'
            'if [ "$1" = "--format" ] && [ "${2:-}" = "json" ]; then\n'
            '  format="--format json "\n'
            "  shift 2\n"
            "fi\n"
            'thinking=""\n'
            'if [ "$1" = "--thinking" ]; then\n'
            '  thinking="--thinking "\n'
            "  shift\n"
            "fi\n"
            'agent=""\n'
            'if [ "$1" = "--agent" ]; then\n'
            '  agent="$2"\n'
            "  shift 2\n"
            "fi\n"
            'if [ -n "$agent" ]; then\n'
            '  line="opencode run ${format}${thinking}--agent $agent $1"\n'
            "else\n"
            '  line="opencode run ${format}${thinking}$1"\n'
            "fi\n"
            'if [ -n "$format" ]; then\n'
            '  printf \'{"response":"%s"}\\n\' "$line"\n'
            "else\n"
            '  printf \'%s\\n\' "$line"\n'
            "fi\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_config(self, tmp_path: Path) -> None:
        toml_config_text = '[defaults]\nrunner = "claude"\n'
        legacy_config_text = "default_runner = claude\n"
        home_config_dir = tmp_path / ".config" / "ccc"
        xdg_config_dir = tmp_path / "xdg" / "ccc"
        home_config_dir.mkdir(parents=True)
        xdg_config_dir.mkdir(parents=True)
        (home_config_dir / "config.toml").write_text(toml_config_text)
        (home_config_dir / "config").write_text(legacy_config_text)
        (xdg_config_dir / "config.toml").write_text(toml_config_text)
        (xdg_config_dir / "config").write_text(legacy_config_text)
        (tmp_path / "legacy-config").write_text(legacy_config_text)

    def _write_agent_preset_config(self, tmp_path: Path) -> None:
        toml_config_text = '[aliases.reviewer]\nagent = "specialist"\n'
        home_config_dir = tmp_path / ".config" / "ccc"
        xdg_config_dir = tmp_path / "xdg" / "ccc"
        home_config_dir.mkdir(parents=True)
        xdg_config_dir.mkdir(parents=True)
        (home_config_dir / "config.toml").write_text(toml_config_text)
        (xdg_config_dir / "config.toml").write_text(toml_config_text)
        (tmp_path / "legacy-config").write_text("")

    def _write_prompt_preset_config(self, tmp_path: Path) -> None:
        toml_config_text = '[aliases.commit]\nprompt = "Commit all changes"\n'
        home_config_dir = tmp_path / ".config" / "ccc"
        xdg_config_dir = tmp_path / "xdg" / "ccc"
        home_config_dir.mkdir(parents=True)
        xdg_config_dir.mkdir(parents=True)
        (home_config_dir / "config.toml").write_text(toml_config_text)
        (xdg_config_dir / "config.toml").write_text(toml_config_text)
        (tmp_path / "legacy-config").write_text("")

    def _write_prompt_mode_config(self, tmp_path: Path, mode: str) -> None:
        toml_config_text = (
            f'[aliases.add-task]\nprompt = "Add this task:"\nshow_thinking = false\nprompt_mode = "{mode}"\n'
        )
        home_config_dir = tmp_path / ".config" / "ccc"
        xdg_config_dir = tmp_path / "xdg" / "ccc"
        home_config_dir.mkdir(parents=True)
        xdg_config_dir.mkdir(parents=True)
        (home_config_dir / "config.toml").write_text(toml_config_text)
        (xdg_config_dir / "config.toml").write_text(toml_config_text)
        (tmp_path / "legacy-config").write_text("")


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Run the ccc contract tests for one implementation."
    )
    parser.add_argument("language", help="Language to test, or 'all'.")
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose unittest output.",
    )
    args = parser.parse_args(argv)

    try:
        SingleImplCccContractTests.selected_languages = _resolve_selected_languages(
            args.language
        )
    except ValueError as exc:
        parser.error(str(exc))

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SingleImplCccContractTests)
    runner = unittest.TextTestRunner(verbosity=2 if args.verbose else 1)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

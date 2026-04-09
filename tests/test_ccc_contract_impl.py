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
EXPECTED = f"opencode run {PROMPT}\n"
CONFIG_DEFAULT_RUNNER_EXPECTED = f"claude -p {PROMPT}\n"
AGENT_FALLBACK_EXPECTED = f"opencode run --agent reviewer {PROMPT}\n"
PRESET_AGENT_EXPECTED = f"opencode run --agent specialist {PROMPT}\n"
PRESET_PROMPT = "Commit all changes"
PRESET_PROMPT_EXPECTED = f"opencode run {PRESET_PROMPT}\n"
PROJECT_LOCAL_PROMPT_EXPECTED = "kimi --thinking --model xdg-model --prompt Repo prompt\n"
CODEX_RUNNER_EXPECTED = f"codex exec {PROMPT}\n"
CLAUDE_RUNNER_EXPECTED = f"claude -p {PROMPT}\n"
KIMI_RUNNER_EXPECTED = f"kimi --prompt {PROMPT}\n"
HELP_USAGE_LINE = 'ccc [controls...] "<Prompt>"'
HELP_SLOT_LINE = (
    "Use a named preset from config; if no preset exists, treat it as an agent"
)
HELP_PRESET_PROMPT_LINE = "Presets can also define a default prompt"
HELP_PROJECT_LOCAL_CONFIG_LINE = ".ccc.toml (searched upward from CWD)"
HELP_GLOBAL_CONFIG_LINE = "XDG_CONFIG_HOME/ccc/config.toml"
HELP_HOME_CONFIG_LINE = "~/.config/ccc/config.toml"
HELP_SHOW_THINKING_SNIPPET = "--show-thinking"
HELP_SANITIZE_OSC_SNIPPET = "--sanitize-osc / --no-sanitize-osc"
HELP_OUTPUT_MODE_SNIPPET = "--output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted>"
HELP_OUTPUT_SUGAR_SNIPPET = ".text / ..text, .json / ..json, .fmt / ..fmt"
HELP_PERMISSION_MODE_SNIPPET = "--permission-mode <safe|auto|yolo|plan>"
HELP_YOLO_SNIPPET = "--yolo / -y"
HELP_DELIMITER_SNIPPET = "Treat all remaining args as prompt text"
SHOW_THINKING_IMPLEMENTATIONS = {"Python", "Rust"}
YOLO_IMPLEMENTATIONS = {"Python", "Rust"}
PROMPT_PRESET_IMPLEMENTATIONS = {"Python", "Rust"}
PROJECT_LOCAL_CONFIG_IMPLEMENTATIONS = {"Python", "Rust"}


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
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"):
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
                        asm_config_path.write_text(
                            f"default_runner = {claude_path}\n"
                        )
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
                    self.assertEqual(result.stdout, CLAUDE_RUNNER_EXPECTED)
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
                    self.assertEqual(result.stderr, "")

    def test_name_without_preset_falls_back_to_agent(self) -> None:
        self._run_with_agent_stub_extra_args_assertion(
            ["@reviewer", PROMPT], self.assert_uses_agent_fallback
        )

    def test_preset_agent_wins_over_name_fallback(self) -> None:
        self._run_with_agent_preset_assertion(self.assert_uses_preset_agent)

    def test_preset_prompt_fills_missing_prompt(self) -> None:
        self._run_with_prompt_preset_assertion(None, self.assert_uses_preset_prompt)

    def test_explicit_prompt_overrides_preset_prompt(self) -> None:
        self._run_with_prompt_preset_assertion(PROMPT, self.assert_equal_output)

    def test_whitespace_prompt_falls_back_to_preset_prompt(self) -> None:
        self._run_with_prompt_preset_assertion("   ", self.assert_uses_preset_prompt)

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
                    self.assert_help_mentions_standard_name_slot(result, HELP_USAGE_LINE)

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
                    self.assertEqual(result.stderr, "")

    def test_permission_mode_maps_to_runner_specific_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            codex_path = bin_dir / "codex"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(codex_path, "codex")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_argv_echo_stub(opencode_path, "opencode")

            cases = {
                "Python": [
                    (["cc", "--permission-mode", "safe"], "claude -p --permission-mode default Fix the failing tests\n", ""),
                    (["cc", "--permission-mode", "auto"], "claude -p --permission-mode auto Fix the failing tests\n", ""),
                    (["c", "--permission-mode", "auto"], "codex exec --full-auto Fix the failing tests\n", ""),
                    (["cc", "--permission-mode", "plan"], "claude -p --permission-mode plan Fix the failing tests\n", ""),
                    (["k", "--permission-mode", "plan"], "kimi --plan --prompt Fix the failing tests\n", ""),
                    (
                        ["k", "--permission-mode", "auto"],
                        "kimi --prompt Fix the failing tests\n",
                        'warning: runner "k" does not support permission mode "auto"; ignoring it\n',
                    ),
                ],
                "Rust": [
                    (["cc", "--permission-mode", "safe"], "claude -p --permission-mode default Fix the failing tests\n", ""),
                    (["cc", "--permission-mode", "auto"], "claude -p --permission-mode auto Fix the failing tests\n", ""),
                    (["c", "--permission-mode", "auto"], "codex exec --full-auto Fix the failing tests\n", ""),
                    (["cc", "--permission-mode", "plan"], "claude -p --permission-mode plan Fix the failing tests\n", ""),
                    (["k", "--permission-mode", "plan"], "kimi --plan --prompt Fix the failing tests\n", ""),
                    (
                        ["k", "--permission-mode", "auto"],
                        "kimi --prompt Fix the failing tests\n",
                        'warning: runner "k" does not support permission mode "auto"; ignoring it\n',
                    ),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="permission-mode"):
                    for extra_args, expected_stdout, expected_stderr in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(result.stderr, expected_stderr)

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
                    result = lang.invoke_extra(
                        ["c", PROMPT], env
                    )
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
                    (["--show-thinking"], "opencode run --thinking Fix the failing tests\n"),
                    (
                        ["cc", "--show-thinking"],
                        "claude -p --thinking enabled --effort low Fix the failing tests\n",
                    ),
                    (
                        ["k", "--show-thinking"],
                        "kimi --thinking --prompt Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (["--show-thinking"], "opencode run --thinking Fix the failing tests\n"),
                    (
                        ["cc", "--show-thinking"],
                        "claude -p --thinking enabled --effort low Fix the failing tests\n",
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
                            result = lang.invoke_with_args(
                                extra_args, PROMPT, env
                            )
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(result.stderr, "")

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
                        "claude -p --thinking enabled --effort high Fix the failing tests\n",
                    ),
                    (
                        ["cc", "+4"],
                        "claude -p --thinking enabled --effort max Fix the failing tests\n",
                    ),
                ],
                "Rust": [
                    (
                        ["cc", "+3"],
                        "claude -p --thinking enabled --effort high Fix the failing tests\n",
                    ),
                    (
                        ["cc", "+4"],
                        "claude -p --thinking enabled --effort max Fix the failing tests\n",
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
                            result = lang.invoke_with_args(
                                extra_args, PROMPT, env
                            )
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
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_argv_echo_stub(opencode_path, "opencode")

            cases = {
                "Python": [
                    (["cc", ".json"], "claude -p --output-format json Fix the failing tests\n"),
                    (
                        ["cc", "..json"],
                        "claude -p --verbose --output-format stream-json Fix the failing tests\n",
                    ),
                    (
                        ["k", "..json"],
                        "kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (["oc", ".json"], "opencode run --format json Fix the failing tests\n"),
                ],
                "Rust": [
                    (["cc", ".json"], "claude -p --output-format json Fix the failing tests\n"),
                    (
                        ["cc", "..json"],
                        "claude -p --verbose --output-format stream-json Fix the failing tests\n",
                    ),
                    (
                        ["k", "..json"],
                        "kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (["oc", ".json"], "opencode run --format json Fix the failing tests\n"),
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
                            self.assertEqual(result.stderr, "")

    def test_formatted_output_mode_sugar_renders_structured_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            claude_path = bin_dir / "claude"
            kimi_path = bin_dir / "kimi"
            opencode_path = bin_dir / "opencode"
            self._write_structured_argv_echo_stub(claude_path, "claude", "claude-code")
            self._write_structured_argv_echo_stub(kimi_path, "kimi", "kimi")
            self._write_structured_argv_echo_stub(opencode_path, "opencode", "opencode")

            cases = {
                "Python": [
                    (["cc", ".fmt"], "[assistant] claude -p --verbose --output-format stream-json Fix the failing tests\n"),
                    (
                        ["cc", "..fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --include-partial-messages Fix the failing tests\n",
                    ),
                    (
                        ["k", ".fmt"],
                        "[assistant] kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (
                        ["k", "..fmt"],
                        "[assistant] kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (["oc", ".fmt"], "[assistant] opencode run --format json Fix the failing tests\n"),
                ],
                "Rust": [
                    (["cc", ".fmt"], "[assistant] claude -p --verbose --output-format stream-json Fix the failing tests\n"),
                    (
                        ["cc", "..fmt"],
                        "[assistant] claude -p --verbose --output-format stream-json --include-partial-messages Fix the failing tests\n",
                    ),
                    (
                        ["k", ".fmt"],
                        "[assistant] kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (
                        ["k", "..fmt"],
                        "[assistant] kimi --print --output-format stream-json --prompt Fix the failing tests\n",
                    ),
                    (["oc", ".fmt"], "[assistant] opencode run --format json Fix the failing tests\n"),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="formatted-output-mode"):
                    for extra_args, expected_stdout in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(result.stderr, "")

    def test_unsupported_output_mode_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_argv_echo_stub(opencode_path, "opencode")

            for lang in self.selected_languages:
                if lang.name not in {"Python", "Rust"}:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name):
                    result = lang.invoke_with_args(["oc", "..json"], PROMPT, env)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("output mode", result.stderr)
                    result = lang.invoke_with_args(["oc", "..fmt"], PROMPT, env)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("output mode", result.stderr)

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
                    self.assertEqual(result.stderr, "")

    def test_double_dash_forces_literal_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            opencode_path = bin_dir / "opencode"
            self._write_argv_echo_stub(opencode_path, "opencode")

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
                        "opencode run +1 @agent :model\n",
                    )
                    self.assertEqual(result.stderr, "")

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
            self._write_argv_echo_stub(claude_path, "claude")
            self._write_argv_echo_stub(codex_path, "codex")
            self._write_argv_echo_stub(kimi_path, "kimi")
            self._write_argv_echo_stub(crush_path, "crush")
            self._write_opencode_yolo_stub(opencode_path)

            cases = {
                "Python": [
                    (["cc", "--yolo"], "claude -p --dangerously-skip-permissions Fix the failing tests\n", ""),
                    (["c", "--yolo"], "codex exec --dangerously-bypass-approvals-and-sandbox Fix the failing tests\n", ""),
                    (["k", "-y"], "kimi --yolo --prompt Fix the failing tests\n", ""),
                    (
                        ["cr", "--yolo"],
                        "crush run Fix the failing tests\n",
                        'warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo\n',
                    ),
                    (["oc", "--yolo"], "opencode run Fix the failing tests\n", '{"permission":"allow"}'),
                ],
                "Rust": [
                    (["cc", "--yolo"], "claude -p --dangerously-skip-permissions Fix the failing tests\n", ""),
                    (["c", "--yolo"], "codex exec --dangerously-bypass-approvals-and-sandbox Fix the failing tests\n", ""),
                    (["k", "-y"], "kimi --yolo --prompt Fix the failing tests\n", ""),
                    (
                        ["cr", "--yolo"],
                        "crush run Fix the failing tests\n",
                        'warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo\n',
                    ),
                    (["oc", "--yolo"], "opencode run Fix the failing tests\n", '{"permission":"allow"}'),
                ],
            }

            for lang in self.selected_languages:
                if lang.name not in cases:
                    continue
                env = self._make_env(opencode_path, lang)
                with self.subTest(language=lang.name, capability="yolo"):
                    for extra_args, expected_stdout, expected_stderr in cases[lang.name]:
                        with self.subTest(language=lang.name, args=extra_args):
                            result = lang.invoke_with_args(extra_args, PROMPT, env)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected_stdout)
                            self.assertEqual(result.stderr, expected_stderr)

    def assert_equal_output(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, EXPECTED)
        self.assertEqual(result.stderr, "")

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

    def assert_uses_configured_default_runner(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CONFIG_DEFAULT_RUNNER_EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_uses_agent_fallback(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, AGENT_FALLBACK_EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_uses_preset_agent(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PRESET_AGENT_EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_uses_preset_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PRESET_PROMPT_EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_help_mentions_standard_name_slot(
        self, result, expected_usage_line
    ) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(expected_usage_line, result.stdout)
        self.assertIn(HELP_SLOT_LINE, result.stdout)

    def assert_help_mentions_show_thinking_flag(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        if any(lang.name in {"Python", "Rust"} for lang in self.selected_languages):
            self.assertIn(HELP_SHOW_THINKING_SNIPPET, result.stdout)
            self.assertIn("show_thinking", result.stdout)

    def assert_help_mentions_sanitize_osc_flag(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_SANITIZE_OSC_SNIPPET, result.stdout)
        self.assertIn("sanitize_osc", result.stdout)

    def assert_help_mentions_output_modes(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_OUTPUT_MODE_SNIPPET, result.stdout)
        self.assertIn(HELP_OUTPUT_SUGAR_SNIPPET, result.stdout)

    def assert_help_mentions_yolo_and_delimiter(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_PERMISSION_MODE_SNIPPET, result.stdout)
        self.assertIn(HELP_YOLO_SNIPPET, result.stdout)
        self.assertIn(HELP_DELIMITER_SNIPPET, result.stdout)

    def assert_help_mentions_preset_prompt(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELP_PRESET_PROMPT_LINE, result.stdout)

    def assert_uses_codex_exec_runner(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CODEX_RUNNER_EXPECTED)
        self.assertEqual(result.stderr, "")

    def _write_opencode_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "run" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
            "printf 'opencode run %s\\n' \"$1\"\n"
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
                f'printf \'{{"type":"assistant","message":{{"content":[{{"type":"text","text":"{runner_name} %s"}}]}}}}\\n\' \"$*\"\n'
                f'printf \'{{"type":"result","subtype":"success","result":"{runner_name} %s"}}\\n\' \"$*\"\n'
            )
        elif schema_name == "kimi":
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"role":"assistant","content":"{runner_name} %s"}}\\n\' \"$*\"\n'
            )
        else:
            body = (
                "#!/bin/sh\n"
                f'printf \'{{"response":"{runner_name} %s"}}\\n\' \"$*\"\n'
            )
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _write_codex_stub(self, path: Path) -> None:
        path.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "exec" ]; then\n'
            "  exit 9\n"
            "fi\n"
            "shift\n"
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
            "printf 'opencode run %s\\n' \"$*\"\n"
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
            'agent=""\n'
            'if [ "$1" = "--agent" ]; then\n'
            '  agent="$2"\n'
            "  shift 2\n"
            "fi\n"
            'if [ -n "$agent" ]; then\n'
            "  printf 'opencode run --agent %s %s\\n' \"$agent\" \"$1\"\n"
            "else\n"
            "  printf 'opencode run %s\\n' \"$1\"\n"
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

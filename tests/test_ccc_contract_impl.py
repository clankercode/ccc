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
CONFIG_DEFAULT_RUNNER_EXPECTED = f"claude {PROMPT}\n"


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
        path.write_text(f"#!/bin/sh\nprintf '{runner_name} %s\\n' \"$1\"\n")
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

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROMPT = "Fix the failing tests"
EXPECTED = f"opencode run {PROMPT}\n"


class CccContractTests(unittest.TestCase):
    def test_cross_language_ccc_happy_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            self._write_opencode_stub(bin_dir / "opencode")

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"

            self.assert_equal_output(
                subprocess.run(
                    ["python3", "python/call_coding_clis/cli.py", PROMPT],
                    cwd=ROOT,
                    env={**env, "PYTHONPATH": str(ROOT / "python")},
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    ["cargo", "run", "--quiet", "--bin", "ccc", "--", PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    ["node", "typescript/src/ccc.js", PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["make", "-C", "c", "build/ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "c/build/ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

    def test_cross_language_ccc_rejects_empty_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            self._write_opencode_stub(bin_dir / "opencode")

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"

            self.assert_rejects_empty(
                subprocess.run(
                    ["python3", "python/call_coding_clis/cli.py", ""],
                    cwd=ROOT,
                    env={**env, "PYTHONPATH": str(ROOT / "python")},
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["cargo", "run", "--quiet", "--bin", "ccc", "--", ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["node", "typescript/src/ccc.js", ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["make", "-C", "c", "build/ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "c/build/ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

    def test_cross_language_ccc_requires_one_prompt_argument(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            self._write_opencode_stub(bin_dir / "opencode")

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["python3", "python/call_coding_clis/cli.py"],
                    cwd=ROOT,
                    env={**env, "PYTHONPATH": str(ROOT / "python")},
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["cargo", "run", "--quiet", "--bin", "ccc"],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["node", "typescript/src/ccc.js"],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["make", "-C", "c", "build/ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "c/build/ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

    def test_cross_language_ccc_rejects_whitespace_only_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            self._write_opencode_stub(bin_dir / "opencode")

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
            whitespace_prompt = "   "

            self.assert_rejects_empty(
                subprocess.run(
                    ["python3", "python/call_coding_clis/cli.py", whitespace_prompt],
                    cwd=ROOT,
                    env={**env, "PYTHONPATH": str(ROOT / "python")},
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "cargo",
                        "run",
                        "--quiet",
                        "--bin",
                        "ccc",
                        "--",
                        whitespace_prompt,
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["node", "typescript/src/ccc.js", whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["make", "-C", "c", "build/ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "c/build/ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

    def assert_equal_output(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, EXPECTED)
        self.assertEqual(result.stderr, "")

    def assert_rejects_empty(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(result.returncode, 0)

    def assert_rejects_missing_prompt(
        self, result: subprocess.CompletedProcess[str]
    ) -> None:
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ccc "<Prompt>"', result.stderr)

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


if __name__ == "__main__":
    unittest.main()

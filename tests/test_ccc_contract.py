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

    def assert_equal_output(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, EXPECTED)

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

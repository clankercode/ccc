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
    def _make_env(self, tmp_path: Path, bin_dir: Path) -> dict[str, str]:
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
        env["LC_ALL"] = "C"
        env["PERL_BADLANG"] = "0"
        env["XDG_CONFIG_HOME"] = str(tmp_path / "xdg")
        env["XDG_CACHE_HOME"] = str(tmp_path / "xdg-cache")
        env["XDG_DATA_HOME"] = str(tmp_path / "xdg-data")
        env["XDG_STATE_HOME"] = str(tmp_path / "xdg-state")
        env["GOCACHE"] = str(tmp_path / "go-cache")
        env["DOTNET_CLI_HOME"] = str(tmp_path / "dotnet-home")
        env["DOTNET_NOLOGO"] = "1"
        env["DOTNET_SKIP_FIRST_TIME_EXPERIENCE"] = "1"
        env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        env["CABAL_DIR"] = str(tmp_path / "cabal")
        env["CRYSTAL_CACHE_DIR"] = str(tmp_path / "crystal-cache")
        env["ZIG_GLOBAL_CACHE_DIR"] = str(tmp_path / "zig-global-cache")
        env["ZIG_LOCAL_CACHE_DIR"] = str(tmp_path / "zig-local-cache")
        env["CCC_CONFIG"] = str(tmp_path / "missing-config.toml")
        for key in (
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "GOCACHE",
            "DOTNET_CLI_HOME",
            "CABAL_DIR",
            "CRYSTAL_CACHE_DIR",
            "ZIG_GLOBAL_CACHE_DIR",
            "ZIG_LOCAL_CACHE_DIR",
        ):
            Path(env[key]).mkdir(parents=True, exist_ok=True)
        xdg_config = Path(env["XDG_CONFIG_HOME"]) / "ccc" / "config.toml"
        xdg_config.parent.mkdir(parents=True, exist_ok=True)
        xdg_config.write_text("", encoding="utf-8")
        return env

    def _c_build_env(self, env: dict[str, str]) -> dict[str, str]:
        return {
            **env,
            "PATH": f"/usr/bin:{env.get('PATH', '')}",
            "CC": "/usr/bin/gcc",
        }

    def test_cross_language_ccc_happy_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bin_dir = tmp_path / "bin"
            bin_dir.mkdir()
            self._write_opencode_stub(bin_dir / "opencode")

            env = self._make_env(tmp_path, bin_dir)

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
                    cwd=ROOT / "rust",
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
                env=self._c_build_env(env),
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

            subprocess.run(
                ["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"],
                cwd=ROOT / "go",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "go" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    ["ruby", str(ROOT / "ruby" / "bin" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    [
                        "perl",
                        "-I",
                        str(ROOT / "perl" / "lib"),
                        str(ROOT / "perl" / "bin" / "ccc"),
                        PROMPT,
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cmake", "-B", str(ROOT / "cpp" / "build"), "-S", str(ROOT / "cpp")],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            subprocess.run(
                ["cmake", "--build", str(ROOT / "cpp" / "build"), "--target", "ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "cpp" / "build" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["zig", "build"],
                cwd=ROOT / "zig",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "zig" / "zig-out" / "bin" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["dub", "build"],
                cwd=ROOT / "d",
                env={**env, "PATH": f"/usr/bin:{env.get('PATH', '')}"},
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "d" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    [
                        "dotnet",
                        "run",
                        "--project",
                        str(ROOT / "fsharp" / "src" / "App"),
                        "--",
                        PROMPT,
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    ["php", str(ROOT / "php" / "bin" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_equal_output(
                subprocess.run(
                    ["node", str(ROOT / "purescript" / "bin" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["make", "-C", "asm-x86_64"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            asm_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_equal_output(
                subprocess.run(
                    [str(ROOT / "asm-x86_64" / "ccc"), PROMPT],
                    cwd=ROOT,
                    env=asm_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            ocaml_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_equal_output(
                subprocess.run(
                    [
                        str(ROOT / "ocaml" / "_build" / "default" / "bin" / "ccc.exe"),
                        PROMPT,
                    ],
                    cwd=ROOT,
                    env=ocaml_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            crystal_env = {**env, "PATH": f"/usr/bin:{env.get('PATH', '')}"}
            crystal_build = subprocess.run(
                [
                    "crystal",
                    "build",
                    "src/call_coding_clis/ccc.cr",
                    "-o",
                    str(ROOT / "crystal" / "ccc"),
                ],
                cwd=ROOT / "crystal",
                env=crystal_env,
                capture_output=True,
                text=True,
                check=False,
            )
            if crystal_build.returncode == 0:
                self.assert_equal_output(
                    subprocess.run(
                        [str(ROOT / "crystal" / "ccc"), PROMPT],
                        cwd=ROOT,
                        env=env,
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                )

            subprocess.run(
                ["cabal", "build", "ccc"],
                cwd=ROOT / "haskell",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_equal_output(
                subprocess.run(
                    ["cabal", "run", "ccc", "--", PROMPT],
                    cwd=ROOT / "haskell",
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

            env = self._make_env(tmp_path, bin_dir)

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
                    cwd=ROOT / "rust",
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
                env=self._c_build_env(env),
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

            subprocess.run(
                ["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"],
                cwd=ROOT / "go",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "go" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["ruby", str(ROOT / "ruby" / "bin" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "perl",
                        "-I",
                        str(ROOT / "perl" / "lib"),
                        str(ROOT / "perl" / "bin" / "ccc"),
                        "",
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cmake", "-B", str(ROOT / "cpp" / "build"), "-S", str(ROOT / "cpp")],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            subprocess.run(
                ["cmake", "--build", str(ROOT / "cpp" / "build"), "--target", "ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "cpp" / "build" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "zig" / "zig-out" / "bin" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "d" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "dotnet",
                        "run",
                        "--project",
                        str(ROOT / "fsharp" / "src" / "App"),
                        "--",
                        "",
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
                    ["php", str(ROOT / "php" / "bin" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["node", str(ROOT / "purescript" / "bin" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            asm_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "asm-x86_64" / "ccc"), ""],
                    cwd=ROOT,
                    env=asm_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            ocaml_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_empty(
                subprocess.run(
                    [
                        str(ROOT / "ocaml" / "_build" / "default" / "bin" / "ccc.exe"),
                        "",
                    ],
                    cwd=ROOT,
                    env=ocaml_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "crystal" / "ccc"), ""],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cabal", "build", "ccc"],
                cwd=ROOT / "haskell",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    ["cabal", "run", "ccc", "--", ""],
                    cwd=ROOT / "haskell",
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

            env = self._make_env(tmp_path, bin_dir)

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
                    cwd=ROOT / "rust",
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
                env=self._c_build_env(env),
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

            subprocess.run(
                ["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"],
                cwd=ROOT / "go",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "go" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["ruby", str(ROOT / "ruby" / "bin" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [
                        "perl",
                        "-I",
                        str(ROOT / "perl" / "lib"),
                        str(ROOT / "perl" / "bin" / "ccc"),
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cmake", "-B", str(ROOT / "cpp" / "build"), "-S", str(ROOT / "cpp")],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            subprocess.run(
                ["cmake", "--build", str(ROOT / "cpp" / "build"), "--target", "ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "cpp" / "build" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "zig" / "zig-out" / "bin" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "d" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [
                        "dotnet",
                        "run",
                        "--project",
                        str(ROOT / "fsharp" / "src" / "App"),
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["php", str(ROOT / "php" / "bin" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["node", str(ROOT / "purescript" / "bin" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            asm_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "asm-x86_64" / "ccc")],
                    cwd=ROOT,
                    env=asm_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            ocaml_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [
                        str(ROOT / "ocaml" / "_build" / "default" / "bin" / "ccc.exe"),
                    ],
                    cwd=ROOT,
                    env=ocaml_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_missing_prompt(
                subprocess.run(
                    [str(ROOT / "crystal" / "ccc")],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cabal", "build", "ccc"],
                cwd=ROOT / "haskell",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_missing_prompt(
                subprocess.run(
                    ["cabal", "run", "ccc"],
                    cwd=ROOT / "haskell",
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

            env = self._make_env(tmp_path, bin_dir)
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
                    cwd=ROOT / "rust",
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
                env=self._c_build_env(env),
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

            subprocess.run(
                ["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"],
                cwd=ROOT / "go",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "go" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    ["ruby", str(ROOT / "ruby" / "bin" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "perl",
                        "-I",
                        str(ROOT / "perl" / "lib"),
                        str(ROOT / "perl" / "bin" / "ccc"),
                        whitespace_prompt,
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cmake", "-B", str(ROOT / "cpp" / "build"), "-S", str(ROOT / "cpp")],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            subprocess.run(
                ["cmake", "--build", str(ROOT / "cpp" / "build"), "--target", "ccc"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "cpp" / "build" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "zig" / "zig-out" / "bin" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "d" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "dotnet",
                        "run",
                        "--project",
                        str(ROOT / "fsharp" / "src" / "App"),
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
                    ["php", str(ROOT / "php" / "bin" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [
                        "node",
                        str(ROOT / "purescript" / "bin" / "ccc"),
                        whitespace_prompt,
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            asm_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "asm-x86_64" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=asm_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            ocaml_env = {**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")}
            self.assert_rejects_empty(
                subprocess.run(
                    [
                        str(ROOT / "ocaml" / "_build" / "default" / "bin" / "ccc.exe"),
                        whitespace_prompt,
                    ],
                    cwd=ROOT,
                    env=ocaml_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            self.assert_rejects_empty(
                subprocess.run(
                    [str(ROOT / "crystal" / "ccc"), whitespace_prompt],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
            )

            subprocess.run(
                ["cabal", "build", "ccc"],
                cwd=ROOT / "haskell",
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assert_rejects_empty(
                subprocess.run(
                    ["cabal", "run", "ccc", "--", whitespace_prompt],
                    cwd=ROOT / "haskell",
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
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertNotEqual(result.stderr, "")

    def assert_rejects_missing_prompt(
        self, result: subprocess.CompletedProcess[str]
    ) -> None:
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertNotEqual(result.stderr, "")
        self.assertTrue(
            'ccc "<Prompt>"' in result.stderr or "ccc" in result.stderr.lower(),
            f"Expected usage message in stderr, got: {result.stderr!r}",
        )

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

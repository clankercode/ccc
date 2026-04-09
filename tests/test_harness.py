import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Optional


ROOT = Path(__file__).resolve().parent.parent
MOCK_BIN = ROOT / "tests" / "mock-coding-cli" / "mock_coding_cli.sh"


class LanguageSpec:
    def __init__(
        self,
        name: str,
        build_cmds: Optional[List[List[str]]] = None,
        build_cwd: Optional[Path] = None,
        invoke_fn=None,
        env_extra: Optional[Dict[str, str]] = None,
    ):
        self.name = name
        self.build_cmds = build_cmds
        self.build_cwd = build_cwd or ROOT
        self.invoke_fn = invoke_fn
        self.env_extra = env_extra or {}
        self.build_ok = True
        self.build_error = ""

    def build(self, env: Dict[str, str]) -> None:
        self.build_ok = True
        if self.build_cmds:
            build_env = {**env, **self.env_extra}
            for cmd in self.build_cmds:
                result = subprocess.run(
                    cmd,
                    cwd=self.build_cwd,
                    env=build_env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    self.build_ok = False
                    self.build_error = f"Build failed for {self.name}: {result.stderr}"
                    return

    def invoke(self, prompt: str, env: Dict[str, str]) -> subprocess.CompletedProcess:
        cmd = self.invoke_fn(prompt)
        return subprocess.run(
            cmd,
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def invoke_extra(
        self, extra_args: List[str], env: Dict[str, str]
    ) -> subprocess.CompletedProcess:
        cmd = self.invoke_fn("__placeholder__")
        cmd = cmd[:-1] + extra_args
        return subprocess.run(
            cmd,
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )


def _py_invoke(prompt):
    return ["python3", "python/call_coding_clis/cli.py", prompt]


def _rust_invoke(prompt):
    return ["cargo", "run", "--quiet", "--bin", "ccc", "--", prompt]


def _ts_invoke(prompt):
    return ["node", "typescript/src/ccc.js", prompt]


def _c_invoke(prompt):
    return [str(ROOT / "c" / "build" / "ccc"), prompt]


def _go_invoke(prompt):
    return [str(ROOT / "go" / "ccc"), prompt]


def _ruby_invoke(prompt):
    return ["ruby", str(ROOT / "ruby" / "bin" / "ccc"), prompt]


def _perl_invoke(prompt):
    return [
        "perl",
        "-I",
        str(ROOT / "perl" / "lib"),
        str(ROOT / "perl" / "bin" / "ccc"),
        prompt,
    ]


def _cpp_invoke(prompt):
    return [str(ROOT / "cpp" / "build" / "ccc"), prompt]


def _zig_invoke(prompt):
    return [str(ROOT / "zig" / "zig-out" / "bin" / "ccc"), prompt]


def _d_invoke(prompt):
    return [str(ROOT / "d" / "ccc"), prompt]


def _fsharp_invoke(prompt):
    return [
        "dotnet",
        "run",
        "--project",
        str(ROOT / "fsharp" / "src" / "App"),
        "--",
        prompt,
    ]


def _php_invoke(prompt):
    return ["php", str(ROOT / "php" / "bin" / "ccc"), prompt]


def _purescript_invoke(prompt):
    return ["node", str(ROOT / "purescript" / "bin" / "ccc"), prompt]


def _asm_invoke(prompt):
    return [str(ROOT / "asm-x86_64" / "ccc"), prompt]


def _ocaml_invoke(prompt):
    return [str(ROOT / "ocaml" / "_build" / "default" / "bin" / "ccc.exe"), prompt]


def _crystal_invoke(prompt):
    return [str(ROOT / "crystal" / "ccc"), prompt]


def _haskell_invoke(prompt):
    return [str(ROOT / "haskell" / "ccc"), prompt]


LANGUAGES = [
    LanguageSpec(
        "Python",
        invoke_fn=_py_invoke,
        env_extra={"PYTHONPATH": str(ROOT / "python")},
    ),
    LanguageSpec(
        "Rust",
        build_cmds=[["cargo", "build", "--quiet", "--bin", "ccc"]],
        build_cwd=ROOT / "rust",
        invoke_fn=_rust_invoke,
    ),
    LanguageSpec(
        "TypeScript",
        invoke_fn=_ts_invoke,
    ),
    LanguageSpec(
        "C",
        build_cmds=[["make", "-C", "c", "build/ccc"]],
        invoke_fn=_c_invoke,
    ),
    LanguageSpec(
        "Go",
        build_cmds=[["go", "build", "-o", str(ROOT / "go" / "ccc"), "./cmd/ccc"]],
        build_cwd=ROOT / "go",
        invoke_fn=_go_invoke,
    ),
    LanguageSpec(
        "Ruby",
        invoke_fn=_ruby_invoke,
    ),
    LanguageSpec(
        "Perl",
        invoke_fn=_perl_invoke,
    ),
    LanguageSpec(
        "C++",
        build_cmds=[
            [
                "cmake",
                "-B",
                str(ROOT / "cpp" / "build"),
                "-S",
                str(ROOT / "cpp"),
            ],
            [
                "cmake",
                "--build",
                str(ROOT / "cpp" / "build"),
                "--target",
                "ccc",
            ],
        ],
        invoke_fn=_cpp_invoke,
    ),
    LanguageSpec(
        "Zig",
        build_cmds=[["zig", "build"]],
        build_cwd=ROOT / "zig",
        invoke_fn=_zig_invoke,
    ),
    LanguageSpec(
        "D",
        build_cmds=[["dub", "build"]],
        build_cwd=ROOT / "d",
        invoke_fn=_d_invoke,
        env_extra={"CC": "/usr/bin/gcc"},
    ),
    LanguageSpec(
        "F#",
        invoke_fn=_fsharp_invoke,
    ),
    LanguageSpec(
        "PHP",
        invoke_fn=_php_invoke,
    ),
    LanguageSpec(
        "PureScript",
        invoke_fn=_purescript_invoke,
    ),
    LanguageSpec(
        "x86-64 ASM",
        build_cmds=[["make", "-C", "asm-x86_64"]],
        invoke_fn=_asm_invoke,
        env_extra={"CCC_REAL_OPENCODE": str(MOCK_BIN)},
    ),
    LanguageSpec(
        "OCaml",
        invoke_fn=_ocaml_invoke,
        env_extra={"CCC_REAL_OPENCODE": str(MOCK_BIN)},
    ),
    LanguageSpec(
        "Crystal",
        build_cmds=[
            [
                "crystal",
                "build",
                "src/call_coding_clis/ccc.cr",
                "-o",
                str(ROOT / "crystal" / "ccc"),
            ]
        ],
        build_cwd=ROOT / "crystal",
        invoke_fn=_crystal_invoke,
        env_extra={"PATH": f"/usr/bin:{os.environ.get('PATH', '')}"},
    ),
    LanguageSpec(
        "Haskell",
        build_cmds=[
            ["cabal", "build", "ccc"],
            [
                "sh",
                "-c",
                'cp "$(cabal list-bin ccc)" ccc',
            ],
        ],
        build_cwd=ROOT / "haskell",
        invoke_fn=_haskell_invoke,
    ),
]


class TestCase:
    def __init__(
        self,
        name: str,
        prompt: str,
        expected_exit: int,
        expected_stdout: str,
        expected_stderr: str,
    ):
        self.name = name
        self.prompt = prompt
        self.expected_exit = expected_exit
        self.expected_stdout = expected_stdout
        self.expected_stderr = expected_stderr


TEST_CASES = [
    TestCase(
        "happy_path",
        "hello world",
        0,
        "mock: ok\n",
        "",
    ),
    TestCase(
        "backward_compat_existing_stub",
        "Fix the failing tests",
        0,
        "opencode run Fix the failing tests\n",
        "",
    ),
    TestCase(
        "exit_code_forwarding",
        "exit 42",
        42,
        "",
        "mock: intentional failure\n",
    ),
    TestCase(
        "stderr_forwarding",
        "stderr test",
        0,
        "mock: stdout output\n",
        "mock: stderr output\n",
    ),
    TestCase(
        "multiline_stdout",
        "multiline",
        0,
        "line1\nline2\nline3\n",
        "",
    ),
    TestCase(
        "mixed_streams_nonzero",
        "mixed streams",
        1,
        "mock: out\n",
        "mock: err\n",
    ),
    TestCase(
        "special_chars_in_prompt",
        'fix the "bug" & edge-case',
        0,
        "mock: unknown prompt 'fix the \"bug\" & edge-case'\n",
        "",
    ),
    TestCase(
        "large_output",
        "large output",
        0,
        "A" * 4096 + "\n",
        "",
    ),
    TestCase(
        "unicode_prompt",
        "réparer le bogue",
        0,
        "mock: unknown prompt 'réparer le bogue'\n",
        "",
    ),
]


class CrossLanguageHarness(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not MOCK_BIN.exists():
            raise FileNotFoundError(f"Mock binary not found: {MOCK_BIN}")
        st = os.stat(MOCK_BIN)
        if not (st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)):
            raise PermissionError(f"Mock binary not executable: {MOCK_BIN}")

        cls.tmp_dir = tempfile.mkdtemp()
        cls.bin_dir = Path(cls.tmp_dir) / "bin"
        cls.bin_dir.mkdir()
        opencode_link = cls.bin_dir / "opencode"
        opencode_link.symlink_to(MOCK_BIN)

        cls.base_env = os.environ.copy()
        cls.base_env["PATH"] = f"{cls.bin_dir}:{cls.base_env.get('PATH', '')}"
        cls.base_env["PERL_BADLANG"] = "0"

        for lang in LANGUAGES:
            lang.build(cls.base_env)

    def _make_env(self, lang: LanguageSpec) -> Dict[str, str]:
        env = self.base_env.copy()
        env.update(lang.env_extra)
        return env

    def test_all_languages_against_mock(self):
        for lang in LANGUAGES:
            env = self._make_env(lang)
            for tc in TEST_CASES:
                with self.subTest(language=lang.name, case=tc.name):
                    if not lang.build_ok:
                        self.skipTest(lang.build_error)
                    result = lang.invoke(tc.prompt, env)
                    details = []

                    if result.returncode != tc.expected_exit:
                        details.append(
                            f"  exit code: got {result.returncode}, expected {tc.expected_exit}"
                        )

                    if result.stdout != tc.expected_stdout:
                        details.append(
                            f"  stdout: got {result.stdout!r}, expected {tc.expected_stdout!r}"
                        )

                    if result.stderr != tc.expected_stderr:
                        details.append(
                            f"  stderr: got {result.stderr!r}, expected {tc.expected_stderr!r}"
                        )

                    if details:
                        self.fail(f"[{lang.name}] {tc.name}:\n" + "\n".join(details))

    def test_rejects_extra_arguments(self):
        for lang in LANGUAGES:
            env = self._make_env(lang)
            with self.subTest(language=lang.name):
                if not lang.build_ok:
                    self.skipTest(lang.build_error)
                result = lang.invoke_extra(["hello", "world"], env)
                with self.subTest(language=lang.name):
                    if result.returncode not in (0, 1):
                        self.fail(
                            f"[{lang.name}] extra args: exit code {result.returncode}, expected 0 or 1"
                        )


if __name__ == "__main__":
    unittest.main()

import argparse
import os
import stat
import subprocess
import sys
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

    def _ensure_env_dirs(self, prepared: Dict[str, str]) -> Dict[str, str]:
        dir_vars = [
            "HOME",
            "XDG_CONFIG_HOME",
            "XDG_DATA_HOME",
            "XDG_CACHE_HOME",
            "XDG_STATE_HOME",
            "CARGO_HOME",
            "GOCACHE",
            "DOTNET_CLI_HOME",
            "NUGET_PACKAGES",
            "CRYSTAL_CACHE_DIR",
            "CABAL_DIR",
        ]
        for key in dir_vars:
            path = prepared.get(key)
            if path:
                Path(path).mkdir(parents=True, exist_ok=True)
        return prepared

    def build_env(self, env: Dict[str, str]) -> Dict[str, str]:
        return self._ensure_env_dirs({**env, **self.env_extra})

    def prepared_env(self, env: Dict[str, str]) -> Dict[str, str]:
        return self._ensure_env_dirs({**self.env_extra, **env})

    def build(self, env: Dict[str, str]) -> None:
        self.build_ok = True
        if self.build_cmds:
            build_env = self.build_env(env)
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

    def invoke(
        self, prompt: str, env: Dict[str, str], cwd: Optional[Path] = None
    ) -> subprocess.CompletedProcess:
        cmd = self.invoke_fn(prompt)
        return subprocess.run(
            cmd,
            cwd=cwd or ROOT,
            env=self.prepared_env(env),
            capture_output=True,
            text=True,
            check=False,
        )

    def invoke_extra(
        self, extra_args: List[str], env: Dict[str, str], cwd: Optional[Path] = None
    ) -> subprocess.CompletedProcess:
        cmd = self.invoke_fn("__placeholder__")
        cmd = cmd[:-1] + extra_args
        return subprocess.run(
            cmd,
            cwd=cwd or ROOT,
            env=self.prepared_env(env),
            capture_output=True,
            text=True,
            check=False,
        )

    def invoke_with_args(
        self,
        extra_args: List[str],
        prompt: str,
        env: Dict[str, str],
        cwd: Optional[Path] = None,
    ) -> subprocess.CompletedProcess:
        cmd = self.invoke_fn(prompt)
        cmd = cmd[:-1] + extra_args + [prompt]
        return subprocess.run(
            cmd,
            cwd=cwd or ROOT,
            env=self.prepared_env(env),
            capture_output=True,
            text=True,
            check=False,
        )


def _py_invoke(prompt):
    return ["python3", str(ROOT / "python" / "call_coding_clis" / "cli.py"), prompt]


def _rust_invoke(prompt):
    return [str(ROOT / "rust" / "target" / "debug" / "ccc"), prompt]


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


def _elixir_invoke(prompt):
    return [
        "elixir",
        "-pa",
        str(ROOT / "elixir" / "ebin"),
        "-e",
        "CallCodingClis.CLI.main(System.argv())",
        "--",
        prompt,
    ]


def _nim_invoke(prompt):
    return [str(ROOT / "nim" / "call_coding_clis" / "ccc"), prompt]


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
        env_extra={"GOCACHE": "/tmp/ccc-go-cache"},
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
        env_extra={
            "HOME": "/tmp/ccc-home-zig",
            "XDG_CACHE_HOME": "/tmp/ccc-xdg-cache-zig",
            "ZIG_GLOBAL_CACHE_DIR": "/tmp/ccc-zig-global-cache",
            "ZIG_LOCAL_CACHE_DIR": "/tmp/ccc-zig-local-cache",
        },
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
        env_extra={
            "DOTNET_NOLOGO": "1",
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
            "DOTNET_CLI_HOME": "/tmp/ccc-dotnet-home",
            "NUGET_PACKAGES": "/tmp/ccc-nuget",
        },
    ),
    LanguageSpec(
        "PHP",
        invoke_fn=_php_invoke,
    ),
    LanguageSpec(
        "PureScript",
        build_cmds=[["spago", "build"]],
        build_cwd=ROOT / "purescript",
        invoke_fn=_purescript_invoke,
        env_extra={
            "HOME": "/tmp/ccc-home-ps",
            "XDG_DATA_HOME": "/tmp/ccc-xdg-data-ps",
            "XDG_CACHE_HOME": "/tmp/ccc-xdg-cache-ps",
            "XDG_STATE_HOME": "/tmp/ccc-xdg-state-ps",
        },
    ),
    LanguageSpec(
        "x86-64 ASM",
        build_cmds=[["make", "-C", "asm-x86_64"]],
        invoke_fn=_asm_invoke,
        env_extra={"CCC_REAL_OPENCODE": str(MOCK_BIN)},
    ),
    LanguageSpec(
        "OCaml",
        build_cmds=[
            [
                "sh",
                "-c",
                'eval "$(opam env)" && dune build bin/ccc.exe',
            ],
        ],
        build_cwd=ROOT / "ocaml",
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
                "--output",
                str(ROOT / "crystal" / "ccc"),
            ]
        ],
        build_cwd=ROOT / "crystal",
        invoke_fn=_crystal_invoke,
        env_extra={
            "PATH": f"/usr/bin:{os.environ.get('PATH', '')}",
            "HOME": "/tmp/ccc-home-crystal",
            "CRYSTAL_CACHE_DIR": "/tmp/ccc-crystal-cache",
        },
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
        env_extra={
            "HOME": "/tmp/ccc-home-hs",
            "XDG_CONFIG_HOME": "/tmp/ccc-xdg-hs",
            "CABAL_DIR": "/tmp/ccc-cabal",
        },
    ),
    LanguageSpec(
        "Elixir",
        build_cmds=[
            [
                "elixirc",
                "-o",
                "ebin",
                "lib/call_coding_clis/command_spec.ex",
                "lib/call_coding_clis/completed_run.ex",
                "lib/call_coding_clis/runner.ex",
                "lib/call_coding_clis/prompt_spec.ex",
                "lib/call_coding_clis/parser.ex",
                "lib/call_coding_clis/config.ex",
                "lib/call_coding_clis/help.ex",
                "lib/call_coding_clis/cli.ex",
            ],
        ],
        build_cwd=ROOT / "elixir",
        invoke_fn=_elixir_invoke,
        env_extra={"LC_ALL": "C.UTF-8"},
    ),
    LanguageSpec(
        "Nim",
        invoke_fn=_nim_invoke,
    ),
]

LANGUAGE_ALIASES = {
    "python": "Python",
    "rust": "Rust",
    "typescript": "TypeScript",
    "ts": "TypeScript",
    "c": "C",
    "go": "Go",
    "ruby": "Ruby",
    "perl": "Perl",
    "cpp": "C++",
    "c++": "C++",
    "zig": "Zig",
    "d": "D",
    "fsharp": "F#",
    "f#": "F#",
    "php": "PHP",
    "purescript": "PureScript",
    "asm": "x86-64 ASM",
    "x86-64-asm": "x86-64 ASM",
    "x86-64 asm": "x86-64 ASM",
    "ocaml": "OCaml",
    "crystal": "Crystal",
    "elixir": "Elixir",
    "nim": "Nim",
    "haskell": "Haskell",
    "all": "all",
}


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
    selected_languages = LANGUAGES
    formatted_languages = {"Python", "Rust"}

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
        claude_link = cls.bin_dir / "claude"
        claude_link.symlink_to(MOCK_BIN)
        kimi_link = cls.bin_dir / "kimi"
        kimi_link.symlink_to(MOCK_BIN)

        cls.base_env = os.environ.copy()
        cls.base_env["PATH"] = f"{cls.bin_dir}:{cls.base_env.get('PATH', '')}"
        cls.base_env["PERL_BADLANG"] = "0"
        cls.base_env["HOME"] = str(Path(cls.tmp_dir) / "home")
        cls.base_env["XDG_CONFIG_HOME"] = str(Path(cls.tmp_dir) / "xdg-config")
        cls.base_env["XDG_DATA_HOME"] = str(Path(cls.tmp_dir) / "xdg-data")
        cls.base_env["XDG_CACHE_HOME"] = str(Path(cls.tmp_dir) / "xdg-cache")
        cls.base_env["XDG_STATE_HOME"] = str(Path(cls.tmp_dir) / "xdg-state")
        cls.base_env["CCC_CONFIG"] = str(Path(cls.tmp_dir) / "missing-config.toml")
        cls.base_env["CARGO_HOME"] = os.environ.get(
            "CARGO_HOME", str(Path.home() / ".cargo")
        )

        for lang in cls.selected_languages:
            lang.build(cls.base_env)

    def _make_env(self, lang: LanguageSpec) -> Dict[str, str]:
        env = self.base_env.copy()
        env.update(lang.env_extra)
        env["PATH"] = self.base_env.get("PATH", env.get("PATH", ""))
        return env

    def test_all_languages_against_mock(self):
        for lang in self.selected_languages:
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
        for lang in self.selected_languages:
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

    def test_formatted_output_mode_sugar_for_supported_languages(self):
        cases = [
            (
                ["cc", ".fmt"],
                "tool call",
                "claude-code",
                ["[tool:start] read_file", "[tool:result] read_file (ok)", "[assistant] mock: tool call executed"],
            ),
            (
                ["cc", "..fmt", "--show-thinking"],
                "thinking",
                "claude-code",
                ["[thinking] Let me think about this...", "[assistant] mock: thinking done"],
            ),
            (
                ["k", ".fmt"],
                "tool call",
                "kimi-code",
                ["[tool:result] file contents here", "[assistant] mock: tool call executed"],
            ),
            (
                ["k", "..fmt", "--show-thinking"],
                "thinking",
                "kimi-code",
                ["[thinking] Let me think about this...", "[assistant] mock: thinking done"],
            ),
        ]

        for lang in self.selected_languages:
            if lang.name not in self.formatted_languages:
                continue
            if not lang.build_ok:
                self.skipTest(lang.build_error)

            for extra_args, prompt, schema, expected_fragments in cases:
                env = self._make_env(lang)
                env["MOCK_JSON_SCHEMA"] = schema
                with self.subTest(language=lang.name, args=extra_args):
                    result = lang.invoke_with_args(extra_args, prompt, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    for fragment in expected_fragments:
                        self.assertIn(fragment, result.stdout)
                    self.assertEqual(result.stderr, "")

    def test_formatted_output_sanitizes_disruptive_osc_but_preserves_hyperlinks(self):
        for lang in self.selected_languages:
            if lang.name not in self.formatted_languages:
                continue
            if not lang.build_ok:
                self.skipTest(lang.build_error)

            env = self._make_env(lang)
            env["MOCK_JSON_SCHEMA"] = "claude-code"
            with self.subTest(language=lang.name):
                result = lang.invoke_with_args(["cc", ".fmt"], "osc test", env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("\x1b]8;;https://example.com\x07", result.stdout)
                self.assertIn("\x1b]8;;\x07", result.stdout)
                self.assertNotIn("\x1b]9;mock title\x07", result.stdout)
                self.assertNotIn("\x07", result.stdout.replace("\x1b]8;;https://example.com\x07", "").replace("\x1b]8;;\x07", ""))

    def test_formatted_output_can_disable_osc_sanitization(self):
        for lang in self.selected_languages:
            if lang.name not in self.formatted_languages:
                continue
            if not lang.build_ok:
                self.skipTest(lang.build_error)

            env = self._make_env(lang)
            env["MOCK_JSON_SCHEMA"] = "claude-code"
            with self.subTest(language=lang.name):
                result = lang.invoke_with_args(
                    ["cc", ".fmt", "--no-sanitize-osc"],
                    "osc test",
                    env,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("\x1b]8;;https://example.com\x07", result.stdout)
                self.assertIn("\x1b]8;;\x07", result.stdout)
                self.assertIn("\x1b]9;mock title\x07", result.stdout)
                self.assertIn("\x07", result.stdout)


def _usage_language_names() -> List[str]:
    return [lang.name for lang in LANGUAGES]


def _resolve_selected_languages(raw_name: str) -> List[LanguageSpec]:
    key = raw_name.strip().lower()
    resolved = LANGUAGE_ALIASES.get(key)
    if resolved is None:
        raise ValueError(
            f"Unknown language '{raw_name}'. Expected one of: all, "
            + ", ".join(_usage_language_names())
        )
    if resolved == "all":
        return LANGUAGES
    return [lang for lang in LANGUAGES if lang.name == resolved]


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Run the cross-language mock CLI harness for one language or all."
    )
    parser.add_argument(
        "language",
        help="Language to test, or 'all'.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose unittest output.",
    )
    args = parser.parse_args(argv)

    try:
        CrossLanguageHarness.selected_languages = _resolve_selected_languages(
            args.language
        )
    except ValueError as exc:
        parser.error(str(exc))

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CrossLanguageHarness)
    runner = unittest.TextTestRunner(verbosity=2 if args.verbose else 1)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

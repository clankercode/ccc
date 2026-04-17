from __future__ import annotations

from dataclasses import dataclass
from importlib import metadata as importlib_metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

try:
    from .parser import RUNNER_REGISTRY
except ImportError:
    from parser import RUNNER_REGISTRY


CANONICAL_RUNNERS = [
    ("opencode", "oc"),
    ("claude", "cc"),
    ("kimi", "k"),
    ("codex", "c/cx"),
    ("roocode", "rc"),
    ("crush", "cr"),
    ("cursor", "cu"),
    ("gemini", "g"),
]

ROOT = Path(__file__).resolve().parents[2]
VERSION_FILE = ROOT / "VERSION"


@dataclass(frozen=True)
class RunnerStatus:
    name: str
    alias: str
    binary: str
    found: bool
    version: str


HELP_TEXT = """\
ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc config
  ccc config --edit [--user|--local]
  ccc add [-g] <alias>
  ccc --print-config
  ccc --help
  ccc -h
  ccc @reviewer --help

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                  opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr), cursor (cu), gemini (g)
  +thinking     Set thinking level: +0..+4 or +none/+low/+med/+mid/+medium/+high/+max/+xhigh
                Claude maps +0 to --thinking disabled and +1..+4 to --thinking enabled with matching --effort
                Kimi maps +0 to --no-thinking and +1..+4 to --thinking
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, runner names select runners before agent fallback
                Presets can also define a default prompt when the user leaves prompt text blank
                prompt_mode lets alias prompts prepend or append text; prepend/append require an explicit prompt argument
  .mode / ..mode
                Output-mode sugar with a shared dot identity:
                  .text / ..text, .json / ..json, .fmt / ..fmt
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported
  --save-session
                Allow the selected runner to save this run in its normal session history
  --cleanup-session
                Try to clean up the created session after the run when no no-persist flag exists

Flags:
  --print-config                         Print the canonical example config.toml and exit
  --help / -h                           Print help and exit, even when mixed with other args
  --version / -v                        Print the ccc version and resolved client versions
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: on; config key: show_thinking)
  --sanitize-osc / --no-sanitize-osc    Strip disruptive OSC control output in human-facing modes
                                        while preserving OSC 8 hyperlinks
                                        (config key: defaults.sanitize_osc)
  --output-log-path / --no-output-log-path
                                        Emit or suppress the parseable run footer on stderr
                                        (default: on; No TOML config key)
  --output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted>
                                        Select raw, streamed, or formatted output handling
                                        (config key: defaults.output_mode)
  --forward-unknown-json                In formatted modes, forward unhandled JSON objects to stderr
  Environment:
    FORCE_COLOR / NO_COLOR              Override TTY detection for formatted human output
                                        (FORCE_COLOR wins if both are set)
  --            Treat all remaining args as prompt text, even if they look like controls

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc --permission-mode auto c "Add tests"
  ccc --yolo cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc --permission-mode plan k "Think before editing"
  ccc ..fmt cc +3 "Investigate the failing test"
  ccc -o stream-json k "Reply with exactly pong"
  ccc @reviewer k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"
  ccc -y -- +1 @agent :model
  ccc --print-config

Config:
  ccc config                            — print every resolved config file path and contents
  ccc config --edit                     — open the selected config in $EDITOR
  ccc config --edit --user              — open XDG_CONFIG_HOME/ccc/config.toml or ~/.config/ccc/config.toml
  ccc config --edit --local             — open the nearest .ccc.toml, or create one in CWD
  ccc add [-g] <alias>                  — prompt for alias settings and write them to config
  ccc add <alias> --runner cc --prompt "Review" --yes
                                        — write an alias non-interactively
  ccc --print-config                    — print the canonical example config.toml
  .ccc.toml (searched upward from CWD)  — project-local presets and defaults
  XDG_CONFIG_HOME/ccc/config.toml       — global defaults when XDG is set
  ~/.config/ccc/config.toml             — legacy global fallback
"""


def _get_version(binary: str) -> str:
    try:
        result = subprocess.run(
            [binary, "--version"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split("\n")[0]
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def _read_ccc_version(version_path: Path) -> str:
    try:
        return version_path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _get_ccc_version() -> str:
    version = _read_ccc_version(VERSION_FILE)
    if version:
        return version
    try:
        return importlib_metadata.version("call-coding-clis")
    except importlib_metadata.PackageNotFoundError:
        return "unknown"


def _read_json_version(package_json_path: Path, expected_name: str) -> str:
    try:
        payload = json.loads(package_json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if payload.get("name") != expected_name:
        return ""
    version = payload.get("version")
    return version if isinstance(version, str) else ""


def _discover_opencode_version(binary_path: str) -> str:
    package_json = Path(os.path.realpath(binary_path)).parent.parent / "package.json"
    return _read_json_version(package_json, "opencode-ai")


def _discover_codex_version(binary_path: str) -> str:
    package_json = Path(os.path.realpath(binary_path)).parent.parent / "package.json"
    version = _read_json_version(package_json, "@openai/codex")
    return f"codex-cli {version}" if version else ""


def _discover_claude_version(binary_path: str) -> str:
    parts = Path(os.path.realpath(binary_path)).parts
    if len(parts) < 3 or parts[-3:-1] != ("claude", "versions"):
        return ""
    return f"{parts[-1]} (Claude Code)" if parts[-1] else ""


def _discover_kimi_version(binary_path: str) -> str:
    real_path = Path(os.path.realpath(binary_path))
    if real_path.parent.name != "bin":
        return ""
    site_packages_root = real_path.parent.parent / "lib"
    if not site_packages_root.is_dir():
        return ""
    for metadata_path in sorted(site_packages_root.glob("python*/site-packages/kimi_cli-*.dist-info/METADATA")):
        try:
            for line in metadata_path.read_text(encoding="utf-8").splitlines():
                if line.startswith("Version: "):
                    version = line.partition(": ")[2].strip()
                    if version:
                        return f"kimi, version {version}"
                    return ""
        except OSError:
            continue
    return ""


def _discover_cursor_version(binary_path: str) -> str:
    package_root = Path(os.path.realpath(binary_path)).parent
    try:
        package = json.loads((package_root / "package.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if package.get("name") != "@anysphere/agent-cli-runtime":
        return ""
    try:
        with (package_root / "index.js").open(encoding="utf-8") as handle:
            text = handle.read(32768)
    except OSError:
        return ""
    match = re.search(r"agent-cli@([A-Za-z0-9._-]+)", text)
    return match.group(1) if match else ""


def _discover_gemini_version(binary_path: str) -> str:
    real_path = Path(os.path.realpath(binary_path))
    candidates = [
        real_path.parent / "package.json",
        real_path.parent.parent / "package.json",
    ]
    try:
        launcher = real_path.read_text(encoding="utf-8")
    except OSError:
        launcher = ""
    is_npx_launcher = "@google/gemini-cli" in launcher
    if is_npx_launcher:
        candidates.extend(
            sorted(
                Path.home().glob(
                    ".npm/_npx/*/node_modules/@google/gemini-cli/package.json"
                )
            )
        )
    for package_json in candidates:
        version = _read_json_version(package_json, "@google/gemini-cli")
        if version:
            return version
    if is_npx_launcher:
        return "npx @google/gemini-cli"
    return ""


def _runner_statuses() -> list[RunnerStatus]:
    statuses: list[RunnerStatus] = []
    for name, alias in CANONICAL_RUNNERS:
        info = RUNNER_REGISTRY.get(name)
        binary = info.binary if info else name
        binary_path = shutil.which(binary)
        found = binary_path is not None
        version = _get_runner_version(name, binary, binary_path) if found and binary_path else ""
        statuses.append(
            RunnerStatus(
                name=name,
                alias=alias,
                binary=binary,
                found=found,
                version=version,
            )
        )
    return statuses


def _get_runner_version(runner_name: str, binary: str, binary_path: str) -> str:
    if runner_name == "opencode":
        version = _discover_opencode_version(binary_path)
    elif runner_name == "codex":
        version = _discover_codex_version(binary_path)
    elif runner_name == "claude":
        version = _discover_claude_version(binary_path)
    elif runner_name == "kimi":
        version = _discover_kimi_version(binary_path)
    elif runner_name == "cursor":
        version = _discover_cursor_version(binary_path)
    elif runner_name == "gemini":
        version = _discover_gemini_version(binary_path)
    else:
        version = ""
    return version if version else _get_version(binary)


def runner_checklist() -> str:
    lines = ["Runners:"]
    for status in _runner_statuses():
        if status.found:
            tag = status.version if status.version else "found"
            lines.append(f"  [+] {status.name:10s} ({status.binary})  {tag}")
        else:
            lines.append(f"  [-] {status.name:10s} ({status.binary})  not found")
    return "\n".join(lines)


def _format_version_report(version: str, statuses: list[RunnerStatus]) -> str:
    lines = [f"ccc version {version}", "Resolved clients:"]
    resolved = 0
    for status in statuses:
        if not status.version:
            continue
        resolved += 1
        lines.append(f"  [+] {status.name:10s} ({status.binary})  {status.version}")
    unresolved = len(statuses) - resolved
    if unresolved:
        lines.append(f"  (and {unresolved} unresolved)")
    return "\n".join(lines)


def print_version() -> None:
    print(_format_version_report(_get_ccc_version(), _runner_statuses()))


def print_help() -> None:
    print(HELP_TEXT + "\n" + runner_checklist())


def print_usage() -> None:
    print(
        'usage: ccc [controls...] "<Prompt>"',
        file=sys.stderr,
    )
    print(runner_checklist(), file=sys.stderr)

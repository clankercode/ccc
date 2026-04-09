from __future__ import annotations

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
]


HELP_TEXT = """\
ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc --help
  ccc -h

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                  opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0..+4 or +none/+low/+med/+mid/+medium/+high/+max/+xhigh
                Claude maps +0 to --thinking disabled and +1..+4 to --thinking enabled with matching --effort
                Kimi maps +0 to --no-thinking and +1..+4 to --thinking
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported

Flags:
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: off; config key: show_thinking)
  --            Treat all remaining args as prompt text, even if they look like controls

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc --permission-mode auto c "Add tests"
  ccc --yolo cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc --permission-mode plan k "Think before editing"
  ccc @reviewer k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"
  ccc -y -- +1 @agent :model

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations, show_thinking
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


def runner_checklist() -> str:
    lines = ["Runners:"]
    for name, alias in CANONICAL_RUNNERS:
        info = RUNNER_REGISTRY.get(name)
        binary = info.binary if info else name
        found = shutil.which(binary) is not None
        if found:
            version = _get_version(binary)
            tag = version if version else "found"
            lines.append(f"  [+] {name:10s} ({binary})  {tag}")
        else:
            lines.append(f"  [-] {name:10s} ({binary})  not found")
    return "\n".join(lines)


def print_help() -> None:
    print(HELP_TEXT + "\n" + runner_checklist())


def print_usage() -> None:
    print(
        'usage: ccc [controls...] "<Prompt>"',
        file=sys.stderr,
    )
    print(runner_checklist(), file=sys.stderr)

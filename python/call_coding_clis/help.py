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
    ("codex", "rc"),
    ("crush", "cr"),
]


HELP_TEXT = """\
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                  opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0..+4 or +none/+low/+med/+mid/+medium/+high/+max/+xhigh
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
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
        'usage: ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"',
        file=sys.stderr,
    )
    print(runner_checklist(), file=sys.stderr)

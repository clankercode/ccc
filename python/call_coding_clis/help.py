from __future__ import annotations

from dataclasses import dataclass
from importlib import metadata as importlib_metadata
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
from typing import TextIO

try:
    from .parser import RUNNER_REGISTRY
except ImportError:
    from parser import RUNNER_REGISTRY

try:
    from .config import load_config
except ImportError:
    from config import load_config

try:
    from .json_output import resolve_human_tty
except ImportError:
    from json_output import resolve_human_tty


CANONICAL_RUNNERS = [
    ("opencode", "oc"),
    ("claude", "cc"),
    ("kimi", "k"),
    ("codex", "c/cx"),
    ("roocode", "rc"),
    ("crush", "cr"),
    ("cursor", "cu"),
    ("gemini", "g"),
    ("pi", "p"),
    ("grok", "gb"),
]
ALIAS_SUMMARY_FIELDS = (
    "runner",
    "provider",
    "model",
    "thinking",
    "show_thinking",
    "sanitize_osc",
    "output_mode",
    "service_tier",
    "standalone",
    "agent",
    "prompt",
    "prompt_mode",
    "fallback_models",
)
BARE_ALIAS_VALUE_RE = re.compile(r"^[A-Za-z0-9._:/+-]+$")

ROOT = Path(__file__).resolve().parents[2]
VERSION_FILE = ROOT / "VERSION"


@dataclass(frozen=True)
class RunnerStatus:
    name: str
    alias: str
    binary: str
    found: bool
    version: str
    elapsed_ns: int | None = None


HELP_TEXT = """\
ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc [controls...] -- "<Prompt starting with control-like tokens>"
  ccc config
  ccc config --edit [--user|--local]
  ccc add [-g] <alias>
  ccc --print-config
  ccc help
  ccc --help
  ccc -h
  ccc @reviewer --help

Controls (free order before the prompt):
  runner        Select which coding CLI to use (default: oc)
                  opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr), cursor (cu), gemini (g), pi (p), grok (gb)
  +thinking     Set thinking level: +0..+6 or +none/+low/+med/+mid/+medium/+high/+xhigh/+max/+ultra
                Levels map 0 none, 1 low, 2 medium, 3 high, 4 xhigh, 5 max, 6 ultra
                Claude maps +0 to --thinking disabled and positive levels to --thinking enabled with matching --effort (capped at max)
                Kimi maps +0 to --no-thinking and positive levels to --thinking
                Codex maps each level to -c model_reasoning_effort (none/low/medium/high/xhigh/max/ultra)
                Runners with fewer tiers clamp +6 down to their top tier
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, runner names select runners before agent fallback
                Presets can also define a default prompt when the user leaves prompt text blank
                prompt_mode lets alias prompts prepend or append text; prepend/append require an explicit prompt argument
                fallback_models retries once per model after a capacity or overload error that happens before any assistant output. Mapped models such as glm-5.3, llmp-glm-5-3, and glm-5.3-flash switch to grok; other models stay on the same runner. JSON and formatted output from that retry is parsed with the fallback runner's schema. Authentication errors and failures after output has started do not fall back. Claude runners are not retried, and MiniMax, Claude, or Astra model ids are skipped.
  .mode / ..mode
                Output-mode sugar with a shared dot identity:
                  .text / ..text, .json / ..json, .fmt / ..fmt
  --permission-mode <safe|auto|yolo|plan>
                Request a higher-level permission profile when the selected runner supports it
  --yolo / -y   Request the runner's lowest-friction auto-approval mode when supported
  --fast / --no-fast
                Select fast/default service tier (Codex: -c service_tier="fast"/"default");
                unsupported runners warn and ignore it
  --service-tier <default|fast|priority|ultrafast>
                Select the Codex service tier; CLI overrides alias and config defaults
  --standalone / --no-standalone
                Opt out of Codex/OpenCode's shared daemon, or allow upstream defaults
  --no-daemon   Alias for --standalone (Codex: codex --no-daemon exec)
  --save-session
                Allow the selected runner to save this run in its normal session history
  --cleanup-session
                Try to clean up the created session after the run when no no-persist flag exists

Flags:
  --print-config                         Print the canonical example config.toml and exit
  help / --help / -h                    Print help and exit, even when mixed with other args
  --version / -v                        Print the ccc version and resolved client versions
  --show-thinking / --no-show-thinking  Request visible thinking output when the selected runner supports it
                                        (default: on; config key: show_thinking)
  --sanitize-osc / --no-sanitize-osc    Strip disruptive OSC control output in human-facing modes
                                        while preserving OSC 8 hyperlinks
                                        (config key: defaults.sanitize_osc)
  --output-log-path / --no-output-log-path
                                        Emit or suppress the parseable run footer on stderr
                                        (default: on; No TOML config key)
  --output-mode / -o <text|stream-text|json|stream-json|formatted|stream-formatted|pass-text|pt|stream-pass-text|stream-pt|pass-json|pj|stream-pass-json|stream-pj>
                                        Select raw, streamed, or formatted output handling
                                        (config key: defaults.output_mode)
  --forward-unknown-json                In formatted modes, forward unhandled JSON objects to stderr
  --timeout-secs <N>                    Kill the runner after N seconds and exit 124
  --runner-arg <ARG>                    Append one raw argument to the resolved runner command before the prompt
  Environment:
    CCC_FWD_UNKNOWN_JSON                Also controls unknown-JSON forwarding; defaults on for now
    FORCE_COLOR / NO_COLOR              Override TTY detection for formatted human output
                                        (FORCE_COLOR wins if both are set)
    CCC_UPDATE_CHECK / CCC_AUTO_UPDATE    Override [update] check / auto_update after runs
    CCC_UPDATE_CACHE / CCC_UPDATE_INTERVAL_HOURS
                                        Override update cache path and re-check interval
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
  ccc c --fast "Write a unit test"
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
  [update] check / auto_update / interval_hours
                                        — after each run, warn when a newer ccc is available;
                                          auto_update can background `cargo install ccc`

Agent tips:
  Run `ccc config` before relying on aliases or defaults; `ccc --help` lists the aliases visible from the current directory.
  Use `ccc @alias "task"` when an alias matches the job, then add explicit runner/model/thinking controls only when they matter.
  Use `--` before prompt text that starts with control-like tokens such as `+1`, `@agent`, or `:model`.
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
    except (OSError, UnicodeError, json.JSONDecodeError):
        return ""
    if not isinstance(payload, dict) or payload.get("name") != expected_name:
        return ""
    version = payload.get("version")
    return version if isinstance(version, str) else ""


def _read_prefix(path: Path, limit: int = 16384) -> str:
    try:
        with path.open("rb") as handle:
            return handle.read(limit).decode("utf-8", errors="replace")
    except OSError:
        return ""


def _launcher_paths(path: Path) -> list[Path]:
    """Read literal shell launcher paths without executing or evaluating the script."""
    launcher = _read_prefix(path)
    if not launcher.startswith("#!"):
        return []
    paths = []
    for token in re.findall(r'''["']([^"'\n]+)["']''', launcher):
        for variable, value in (
            ("HOME", str(Path.home())),
            ("basedir", str(path.parent)),
            ("SCRIPT_DIR", str(path.parent)),
        ):
            token = token.replace("${" + variable + "}", value)
            token = re.sub(r"\$" + variable + r"\b", lambda _: value, token)
        if token.startswith("~/"):
            token = str(Path.home()) + token[1:]
        if token.startswith("/") and not any(ch in token for ch in "$`\n"):
            candidate = Path(token)
            if candidate.is_file():
                paths.append(candidate.resolve())
    return paths


def _node_package_version(binary_path: str, names: tuple[str, ...]) -> str:
    def read_package(candidate: Path) -> str:
        for parent in list(candidate.parents)[:6]:
            for name in names:
                version = _read_json_version(parent / "package.json", name)
                if version:
                    return version
        return ""

    path = Path(os.path.realpath(binary_path))
    version = read_package(path)
    if version:
        return version
    for candidate in _launcher_paths(path):
        version = read_package(candidate)
        if version:
            return version
    return ""


def _discover_opencode_version(binary_path: str) -> str:
    path = Path(os.path.realpath(binary_path))
    if path.name == "opencode-cli":
        version = _read_prefix(path.with_name("opencode-cli.version"), 128).strip()
        if re.fullmatch(r"[0-9][A-Za-z0-9._+-]*", version):
            return f"opencode v{version}"
    return _node_package_version(binary_path, ("opencode-ai",))


def _discover_codex_version(binary_path: str) -> str:
    version = _node_package_version(binary_path, ("@openai/codex",))
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
    try:
        receipt = json.loads((real_path.parent.parent / "updates" / "install.json").read_text(encoding="utf-8"))
        installed = receipt.get("lastSuccess") if isinstance(receipt, dict) else None
        version = installed.get("version") if isinstance(installed, dict) else None
        if isinstance(version, str) and re.fullmatch(r"[0-9][A-Za-z0-9._+-]*", version):
            return version
    except (OSError, UnicodeError, json.JSONDecodeError):
        pass
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
    except (OSError, UnicodeError, json.JSONDecodeError):
        return ""
    if not isinstance(package, dict) or package.get("name") != "@anysphere/agent-cli-runtime":
        return ""
    try:
        with (package_root / "index.js").open("rb") as handle:
            overlap = b""
            # Bounded streaming reads also handle modern bundles with dynamic Sentry releases.
            for _ in range(256):
                chunk = handle.read(65536)
                if not chunk:
                    break
                text = overlap + chunk
                match = re.search(rb"agent-cli@(\d[A-Za-z0-9._-]*)", text)
                if not match:
                    match = re.search(rb'''option:version["'][^\n]{0,128}?=["'](\d[A-Za-z0-9._-]*)["']''', text)
                if match and match.end() < len(text):
                    return match.group(1).decode("ascii")
                overlap = text[-512:]
    except OSError:
        return ""
    return ""


def _discover_crush_version(binary_path: str) -> str:
    """Read the Go module version from an ELF section, without loading the executable."""
    try:
        with open(binary_path, "rb") as handle:
            header = handle.read(64)
            if len(header) < 64 or header[:4] != b"\x7fELF" or header[4] not in (1, 2) or header[5] not in (1, 2):
                return ""
            endian = "<" if header[5] == 1 else ">"
            wide = header[4] == 2
            offset = struct.unpack_from(endian + ("Q" if wide else "I"), header, 40 if wide else 32)[0]
            size, count, names_index = struct.unpack_from(endian + "HHH", header, 58 if wide else 46)
            section_format = endian + ("IIQQQQIIQQ" if wide else "IIIIIIIIII")
            if size < struct.calcsize(section_format) or size > 256 or not 0 < count <= 4096 or names_index >= count:
                return ""
            handle.seek(offset)
            table = handle.read(size * count)
            sections = [struct.unpack_from(section_format, table, i * size) for i in range(count)]
            names_section = sections[names_index]
            if names_section[5] > 1048576:
                return ""
            handle.seek(names_section[4])
            names = handle.read(names_section[5])
            for section in sections:
                if names[section[0]:].split(b"\0", 1)[0] != b".go.buildinfo" or section[5] > 1048576:
                    continue
                handle.seek(section[4])
                data = handle.read(section[5])
                if not data.startswith(b"\xff Go buildinf:"):
                    return ""
                match = re.search(rb"\nmod\tgithub.com/charmbracelet/crush\t(v[0-9][A-Za-z0-9._+-]*)\t", data)
                return "crush version " + match.group(1).decode("ascii") if match else ""
    except (OSError, ValueError, OverflowError, struct.error, UnicodeError):
        pass
    return ""


def _discover_gemini_version(binary_path: str) -> str:
    real_path = Path(os.path.realpath(binary_path))
    candidates = [
        real_path.parent / "package.json",
        real_path.parent.parent / "package.json",
    ]
    launcher = _read_prefix(real_path)
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


def _discover_grok_version(binary_path: str) -> str:
    grok_home = Path(os.environ.get("GROK_HOME") or (Path.home() / ".grok"))
    version_json = grok_home / "version.json"
    try:
        payload = json.loads(version_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        payload = None
    if isinstance(payload, dict):
        version = payload.get("version")
        if isinstance(version, str) and version.strip():
            return f"grok {version.strip()}"
    return ""


def _runner_statuses() -> list[RunnerStatus]:
    statuses: list[RunnerStatus] = []
    for name, alias in CANONICAL_RUNNERS:
        info = RUNNER_REGISTRY.get(name)
        binary = info.binary if info else name
        binary_path = shutil.which(binary)
        found = binary_path is not None
        version = ""
        elapsed_ns = None
        if binary_path is not None:
            started_ns = time.monotonic_ns()
            version = _get_runner_version(name, binary, binary_path)
            elapsed_ns = time.monotonic_ns() - started_ns
        statuses.append(
            RunnerStatus(
                name=name,
                alias=alias,
                binary=binary,
                found=found,
                version=version,
                elapsed_ns=elapsed_ns,
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
    elif runner_name == "grok":
        version = _discover_grok_version(binary_path)
    elif runner_name == "pi":
        version = _node_package_version(binary_path, ("@earendil-works/pi-coding-agent", "@mariozechner/pi-coding-agent"))
    elif runner_name == "crush":
        version = _discover_crush_version(binary_path)
    else:
        version = ""
    return version if version else _get_version(binary)


def _runner_color_enabled(stream: TextIO) -> bool:
    return resolve_human_tty(
        stream.isatty(),
        os.environ.get("FORCE_COLOR"),
        os.environ.get("NO_COLOR"),
    )


def _format_runner_rows(statuses: list[RunnerStatus], *, color: bool) -> list[str]:
    tags = [
        (status.version or "found") if status.found else "not found"
        for status in statuses
    ]
    binary_width = max((len(status.binary) for status in statuses), default=0)
    tag_width = max((len(tag) for tag in tags), default=0)
    lines = []
    for status, tag in zip(statuses, tags):
        elapsed = "-"
        if status.found and status.elapsed_ns is not None:
            elapsed = f"{status.elapsed_ns / 1_000_000:.1f} ms"
            if color and status.elapsed_ns > 50_000_000:
                elapsed = f"\x1b[31m{elapsed}\x1b[0m"
        mark = "+" if status.found else "-"
        lines.append(
            f"  [{mark}] {status.binary:<{binary_width}}  {tag:<{tag_width}}  {elapsed}"
        )
    return lines


def runner_checklist(*, stream: TextIO | None = None) -> str:
    if stream is None:
        stream = sys.stdout
    return "\n".join(
        ["Runners:"]
        + _format_runner_rows(_runner_statuses(), color=_runner_color_enabled(stream))
    )


def _format_alias_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = str(value).replace("\r", " ").replace("\n", " ")
    if BARE_ALIAS_VALUE_RE.match(text):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _format_alias_summary(alias: object) -> str:
    fields: list[str] = []
    for key in ALIAS_SUMMARY_FIELDS:
        value = getattr(alias, key)
        if key == "fallback_models":
            if not value:
                continue
            fields.append(f"{key}={','.join(str(item) for item in value)}")
            continue
        if value is not None:
            fields.append(f"{key}={_format_alias_value(value)}")
    return " ".join(fields) if fields else "(empty)"


def alias_checklist() -> str:
    config = load_config()
    lines = ["Configured aliases:"]
    if not config.aliases:
        lines.append("  (none)")
        return "\n".join(lines)

    for name in sorted(config.aliases):
        lines.append(f"  @{name:<11} {_format_alias_summary(config.aliases[name])}")
    return "\n".join(lines)


def _format_version_report(
    version: str, statuses: list[RunnerStatus], *, stream: TextIO | None = None
) -> str:
    if stream is None:
        stream = sys.stdout
    lines = [f"ccc version {version}", "Resolved clients:"]
    resolved = [status for status in statuses if status.version]
    lines.extend(
        _format_runner_rows(resolved, color=_runner_color_enabled(stream))
    )
    unresolved = len(statuses) - len(resolved)
    if unresolved:
        lines.append(f"  (and {unresolved} unresolved)")
    return "\n".join(lines)


def print_version() -> None:
    print(_format_version_report(_get_ccc_version(), _runner_statuses()))


def print_help() -> None:
    print(HELP_TEXT + "\n" + alias_checklist() + "\n\n" + runner_checklist())


def print_usage() -> None:
    print(
        'usage: ccc [controls...] "<Prompt>"',
        file=sys.stderr,
    )
    print(runner_checklist(stream=sys.stderr), file=sys.stderr)

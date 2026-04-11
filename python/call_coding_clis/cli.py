from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re

try:
    from .json_output import (
        FormattedRenderer,
        StructuredStreamProcessor,
        parse_json_output,
        render_parsed,
    )
    from .json_output import resolve_human_tty
    from .runner import CommandSpec, Runner
    from .parser import (
        parse_args,
        resolve_command,
        resolve_output_plan,
        resolve_sanitize_osc,
        resolve_show_thinking,
        AliasDef,
    )
    from .config import (
        find_alias_write_path,
        find_config_command_path,
        load_config,
        normalize_alias_name,
        render_alias_block,
        render_example_config,
        write_alias_block,
    )
    from .help import print_help, print_usage
except ImportError:
    from json_output import (
        FormattedRenderer,
        StructuredStreamProcessor,
        parse_json_output,
        render_parsed,
    )
    from json_output import resolve_human_tty
    from runner import CommandSpec, Runner
    from parser import (
        parse_args,
        resolve_command,
        resolve_output_plan,
        resolve_sanitize_osc,
        resolve_show_thinking,
        AliasDef,
    )
    from config import (
        find_alias_write_path,
        find_config_command_path,
        load_config,
        normalize_alias_name,
        render_alias_block,
        render_example_config,
        write_alias_block,
    )
    from help import print_help, print_usage


ALIAS_FIELDS = {
    "runner",
    "provider",
    "model",
    "thinking",
    "show_thinking",
    "sanitize_osc",
    "output_mode",
    "agent",
    "prompt",
    "prompt_mode",
}

THINKING_ALIASES = {
    "none": 0,
    "low": 1,
    "medium": 2,
    "med": 2,
    "mid": 2,
    "high": 3,
    "max": 4,
    "xhigh": 4,
}
OUTPUT_MODE_CHOICES = ["text", "stream-text", "json", "stream-json", "formatted", "stream-formatted"]
PROMPT_MODE_CHOICES = ["default", "prepend", "append"]


def build_prompt_spec(prompt: str) -> CommandSpec:
    normalized_prompt = prompt.strip()
    if not normalized_prompt:
        raise ValueError("prompt must not be empty")
    return CommandSpec(argv=["opencode", "run", normalized_prompt])


def _apply_real_runner_override(spec: CommandSpec) -> None:
    if not spec.argv:
        return
    env_var_by_binary = {
        "opencode": "CCC_REAL_OPENCODE",
        "claude": "CCC_REAL_CLAUDE",
        "kimi": "CCC_REAL_KIMI",
    }
    env_var = env_var_by_binary.get(spec.argv[0])
    if not env_var:
        return
    override = os.environ.get(env_var, "")
    if override:
        spec.argv[0] = override


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)

    if not args:
        print_usage()
        return 1

    if any(token in {"--help", "-h"} for token in args):
        print_help()
        return 0

    if args and args[0] == "add":
        return _add_alias_command(args[1:])

    if args == ["config"]:
        config_path = find_config_command_path()
        if config_path is None:
            explicit = os.environ.get("CCC_CONFIG", "").strip()
            if explicit:
                print(
                    f"No config file found at {explicit}",
                    file=sys.stderr,
                )
            else:
                print(
                    "No config file found in .ccc.toml, XDG_CONFIG_HOME/ccc/config.toml, or ~/.config/ccc/config.toml",
                    file=sys.stderr,
                )
            return 1
        try:
            content = config_path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"Failed to read config file {config_path}: {exc}", file=sys.stderr)
            return 1
        print(f"Config path: {config_path}")
        print(content, end="")
        return 0

    parsed = parse_args(args)
    if parsed.print_config:
        if args != ["--print-config"]:
            print("--print-config must be used on its own", file=sys.stderr)
            return 1
        print(render_example_config(), end="")
        return 0

    config = load_config()
    try:
        argv_list, env_overrides, warnings = resolve_command(parsed, config)
        output_plan = resolve_output_plan(parsed, config)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    spec = CommandSpec(argv=argv_list, env=env_overrides)

    _apply_real_runner_override(spec)

    for warning in warnings:
        print(warning, file=sys.stderr)
    for warning in _session_persistence_pre_run_warnings(
        parsed.save_session,
        parsed.cleanup_session,
        output_plan.runner_name,
    ):
        print(warning, file=sys.stderr)

    runner = Runner()
    show_thinking = resolve_show_thinking(parsed, config)
    sanitize_osc = resolve_sanitize_osc(parsed, config)
    forward_unknown_json = parsed.forward_unknown_json
    human_tty = resolve_human_tty(
        sys.stdout.isatty(),
        os.environ.get("FORCE_COLOR"),
        os.environ.get("NO_COLOR"),
    )

    if output_plan.mode == "json":
        result = runner.run(spec)
        stdout = _sanitize_raw_output(result.stdout, output_plan.runner_name)
        stderr = _sanitize_raw_output(result.stderr, output_plan.runner_name)
        if stdout:
            print(stdout, end="")
        if stderr:
            print(stderr, end="", file=sys.stderr)
        _print_cleanup_warnings(
            parsed.cleanup_session, output_plan.runner_name, spec, result
        )
        return result.exit_code

    if output_plan.mode == "text":
        result = runner.run(spec)
        stdout = _sanitize_raw_output(result.stdout, output_plan.runner_name)
        stderr = _sanitize_raw_output(result.stderr, output_plan.runner_name)
        if stdout:
            print(stdout, end="")
        if stderr:
            print(stderr, end="", file=sys.stderr)
        _print_cleanup_warnings(
            parsed.cleanup_session, output_plan.runner_name, spec, result
        )
        return result.exit_code

    if output_plan.mode in {"stream-text", "stream-json"}:
        result = runner.stream(
            spec,
            lambda channel, chunk: print(
                chunk,
                end="",
                file=sys.stdout if channel == "stdout" else sys.stderr,
            ),
        )
        _print_cleanup_warnings(
            parsed.cleanup_session, output_plan.runner_name, spec, result
        )
        return result.exit_code

    if output_plan.mode == "formatted":
        result = runner.run(spec)
        stderr = _filtered_human_stderr(result.stderr, output_plan.runner_name)
        if stderr:
            print(_sanitize_human_output(stderr, sanitize_osc), end="", file=sys.stderr)
        parsed_output = parse_json_output(result.stdout, output_plan.schema or "")
        rendered = render_parsed(
            parsed_output,
            show_thinking=show_thinking,
            tty=human_tty,
        )
        if rendered:
            print(_sanitize_human_output(rendered, sanitize_osc))
        if forward_unknown_json:
            for raw_line in parsed_output.unknown_json_lines:
                print(raw_line, file=sys.stderr)
        _print_cleanup_warnings(
            parsed.cleanup_session, output_plan.runner_name, spec, result
        )
        return result.exit_code

    renderer = FormattedRenderer(
        show_thinking=show_thinking,
        tty=human_tty,
    )
    processor = StructuredStreamProcessor(output_plan.schema or "", renderer)
    stderr_filter = _HumanStderrFilter(output_plan.runner_name)
    result = runner.stream(
        spec,
        lambda channel, chunk: _handle_structured_chunk(
            channel,
            chunk,
            processor,
            forward_unknown_json,
            stderr_filter,
            sanitize_osc,
        ),
    )
    trailing = processor.finish()
    if trailing:
        print(_sanitize_human_output(trailing, sanitize_osc))
    trailing_stderr = stderr_filter.finish()
    if trailing_stderr:
        print(
            _sanitize_human_output(trailing_stderr, sanitize_osc),
            end="",
            file=sys.stderr,
        )
    if forward_unknown_json:
        for raw_line in processor.take_unknown_json_lines():
            print(raw_line, file=sys.stderr)
    _print_cleanup_warnings(
        parsed.cleanup_session, output_plan.runner_name, spec, result
    )
    return result.exit_code


def _add_alias_command(args: list[str]) -> int:
    try:
        global_only, name, alias, unset_fields, yes, replace = _parse_add_alias_args(args)
        config_path = find_alias_write_path(global_only=global_only)
        current_config = load_config(config_path) if config_path.exists() else None
        current_alias = current_config.aliases.get(name) if current_config else None
        print(f"Config path: {config_path}")

        mode = "replace" if replace else "modify"
        if current_alias and not yes:
            mode = _ask_existing_alias_action(name, current_alias)
            if mode == "cancel":
                print(f"Cancelled; alias @{name} unchanged")
                return 0

        if current_alias and mode == "modify":
            final_alias = _merge_alias(current_alias, alias, unset_fields)
        else:
            final_alias = alias

        if not yes:
            final_alias = _prompt_alias_fields(final_alias, keep_current=current_alias is not None and mode == "modify")
            print(render_alias_block(name, final_alias), end="")
            if not _confirm("Write this alias?"):
                print(f"Cancelled; alias @{name} unchanged")
                return 0
        elif current_alias is None and not _alias_has_any_field(final_alias):
            print("ccc add --yes requires at least one alias field", file=sys.stderr)
            return 1

        write_alias_block(config_path, name, final_alias)
        print(_format_written_alias(name, final_alias), end="")
        return 0
    except (EOFError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


def _parse_add_alias_args(args: list[str]) -> tuple[bool, str, AliasDef, set[str], bool, bool]:
    global_only = False
    yes = False
    replace = False
    name: str | None = None
    alias = AliasDef()
    unset_fields: set[str] = set()
    index = 0
    while index < len(args):
        token = args[index]
        if token == "-g":
            global_only = True
        elif token == "--yes":
            yes = True
        elif token == "--replace":
            replace = True
        elif token == "--unset":
            value, index = _read_option_value(args, index, token)
            if value not in ALIAS_FIELDS:
                raise ValueError(f"unknown alias field for --unset: {value}")
            unset_fields.add(value)
        elif token in {"--show-thinking", "--no-show-thinking"}:
            alias.show_thinking = token == "--show-thinking"
        elif token in {"--sanitize-osc", "--no-sanitize-osc"}:
            alias.sanitize_osc = token == "--sanitize-osc"
        elif token.startswith("--"):
            field = token[2:].replace("-", "_")
            value, index = _read_option_value(args, index, token)
            _set_alias_field(alias, field, value)
        elif name is None:
            name = normalize_alias_name(token)
        else:
            raise ValueError(f"unexpected argument: {token}")
        index += 1
    if name is None:
        raise ValueError("usage: ccc add [-g] <alias> [alias options]")
    for field in unset_fields:
        if getattr(alias, field) is not None:
            raise ValueError(f"--unset {field} conflicts with --{field.replace('_', '-')}")
    return global_only, name, alias, unset_fields, yes, replace


def _read_option_value(args: list[str], index: int, token: str) -> tuple[str, int]:
    if index + 1 >= len(args):
        raise ValueError(f"{token} requires a value")
    return args[index + 1], index + 1


def _set_alias_field(alias: AliasDef, field: str, value: str) -> None:
    if field not in ALIAS_FIELDS:
        raise ValueError(f"unknown ccc add option: --{field.replace('_', '-')}")
    if field == "thinking":
        alias.thinking = _parse_add_thinking(value)
    elif field == "output_mode":
        if value not in {"text", "stream-text", "json", "stream-json", "formatted", "stream-formatted"}:
            raise ValueError("output_mode must be one of: text, stream-text, json, stream-json, formatted, stream-formatted")
        alias.output_mode = value
    elif field == "prompt_mode":
        if value not in {"default", "prepend", "append"}:
            raise ValueError("prompt_mode must be one of: default, prepend, append")
        alias.prompt_mode = value
    elif field in {"show_thinking", "sanitize_osc"}:
        setattr(alias, field, _parse_add_bool(value))
    else:
        setattr(alias, field, value)


def _parse_add_thinking(value: str) -> int:
    lowered = value.lower()
    if lowered in THINKING_ALIASES:
        return THINKING_ALIASES[lowered]
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ValueError("thinking must be 0, 1, 2, 3, 4, none, low, medium, high, max, or xhigh") from exc
    if parsed not in {0, 1, 2, 3, 4}:
        raise ValueError("thinking must be 0, 1, 2, 3, or 4")
    return parsed


def _parse_add_bool(value: str) -> bool:
    lowered = value.strip().lower()
    if lowered in {"1", "true", "yes", "y", "on"}:
        return True
    if lowered in {"0", "false", "no", "n", "off"}:
        return False
    raise ValueError("boolean values must be true or false")


def _ask_existing_alias_action(name: str, current_alias: AliasDef) -> str:
    print(f"Alias @{name} already exists:")
    print(render_alias_block(name, current_alias), end="")
    return _choose(
        "Existing alias action",
        [
            ("modify", "m", "modify", {"modify"}),
            ("replace", "r", "replace", {"replace"}),
            ("cancel", "c", "cancel", {"cancel"}),
        ],
        default=1,
    )


def _prompt_alias_fields(alias: AliasDef, keep_current: bool) -> AliasDef:
    result = AliasDef(**{field: getattr(alias, field) for field in ALIAS_FIELDS})
    prompts = [
        ("runner", "Runner"),
        ("provider", "Provider"),
        ("model", "Model"),
        ("thinking", "Thinking 0-4"),
        ("show_thinking", "Show thinking true/false"),
        ("sanitize_osc", "Sanitize OSC true/false"),
        ("output_mode", "Output mode"),
        ("agent", "Agent"),
        ("prompt", "Prompt"),
        ("prompt_mode", "Prompt mode"),
    ]
    for field, label in prompts:
        current = getattr(result, field)
        suffix = f" [{current}]" if current is not None else " [default]"
        if field == "thinking":
            choice = _choose_optional_field(
                label,
                suffix,
                [
                    ("unset", "u", None, {"unset", "default"}),
                    ("none", "n", 0, {"none"}),
                    ("low", "l", 1, {"low"}),
                    ("medium", "m", 2, {"medium", "med", "mid"}),
                    ("high", "h", 3, {"high"}),
                    ("xhigh", "x", 4, {"xhigh", "max"}),
                ],
            )
            if choice is not _KEEP_CURRENT:
                result.thinking = choice
            continue
        if field in {"show_thinking", "sanitize_osc"}:
            choice = _choose_optional_field(
                label,
                suffix,
                [
                    ("unset", "u", None, {"unset", "default"}),
                    ("true", "t", True, {"true", "yes", "y", "on"}),
                    ("false", "f", False, {"false", "no", "n", "off"}),
                ],
            )
            if choice is not _KEEP_CURRENT:
                setattr(result, field, choice)
            continue
        if field == "output_mode":
            choice = _choose_optional_field(
                label,
                suffix,
                [("unset", "u", None, {"unset", "default"})]
                + [(mode, _mode_key(mode), mode, {mode}) for mode in OUTPUT_MODE_CHOICES],
            )
            if choice is not _KEEP_CURRENT:
                result.output_mode = choice
            continue
        if field == "prompt_mode":
            choice = _choose_optional_field(
                label,
                suffix,
                [("unset", "u", None, {"unset"})]
                + [(mode, mode[0], mode, {mode}) for mode in PROMPT_MODE_CHOICES],
            )
            if choice is not _KEEP_CURRENT:
                result.prompt_mode = choice
            continue
        answer = input(f"{label}{suffix}: ").strip()
        if answer == "":
            continue
        if answer.lower() in {"default", "unset"}:
            setattr(result, field, None)
        else:
            _set_alias_field(result, field, answer)
    return result


def _confirm(prompt: str) -> bool:
    return _choose(
        prompt,
        [
            ("yes", "y", True, {"yes"}),
            ("no", "n", False, {"no"}),
        ],
        default=2,
    )


_KEEP_CURRENT = object()
_MENU_RESET = "\x1b[0m"


def _menu_color_enabled() -> bool:
    if os.environ.get("FORCE_COLOR"):
        return True
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def _menu_style(text: str, code: str, enabled: bool) -> str:
    if not enabled:
        return text
    return f"\x1b[{code}m{text}{_MENU_RESET}"


def _format_written_alias(name: str, alias: AliasDef) -> str:
    heading = _menu_style(f"✓  Alias @{name} written", "1;32", _menu_color_enabled())
    block = render_alias_block(name, alias)
    indented_block = "".join(f"  {line}" for line in block.splitlines(keepends=True))
    return f"\n{heading}\n\n{indented_block}"


def _mode_key(mode: str) -> str:
    return {
        "stream-text": "st",
        "stream-json": "sj",
        "stream-formatted": "sf",
    }.get(mode, mode[0])


def _choose_optional_field(label: str, suffix: str, choices: list[tuple[str, str, object, set[str]]]) -> object:
    return _choose(f"{label}{suffix}", choices, default=None, blank_value=_KEEP_CURRENT)


def _choice_marker(key: str, label: str) -> str:
    if not key:
        return label
    if len(key) == 1 and label.startswith(key):
        return f"[{key}]{label[1:]}"
    return f"[{key}] {label}"


def _choose(
    prompt: str,
    choices: list[tuple[str, str, object, set[str]]],
    *,
    default: int | None,
    blank_value: object | None = None,
) -> object:
    markers = ", ".join(
        _choice_marker(key, label)
        for label, key, _, _ in choices
    )
    while True:
        color = _menu_color_enabled()
        if default is not None:
            default_label = choices[default - 1][1] or choices[default - 1][0]
        elif blank_value is not None:
            default_label = "keep"
        else:
            default_label = "none"
        answer = input(
            f"{_menu_style(prompt, '1;36', color)} "
            f"{_menu_style(f'(1-{len(choices)})', '2', color)}: \n"
            f"{_menu_style(f'  {markers}', '32', color)}\n"
            f"  {_menu_style('default', '2', color)} {_menu_style(default_label, '33', color)} | "
            f"{_menu_style('choice >', '1;36', color)} "
        ).strip().lower()
        if answer == "":
            if default is not None:
                return choices[default - 1][2]
            return blank_value
        for index, (label, key, value, aliases) in enumerate(choices, 1):
            accepted = {str(index), label, key, *aliases}
            if answer in accepted:
                return value
        print(_menu_style("Please choose one of: ", "31", color) + ", ".join(str(index) for index in range(1, len(choices) + 1)) + ".")


def _merge_alias(current: AliasDef, overlay: AliasDef, unset_fields: set[str]) -> AliasDef:
    result = AliasDef(**{field: getattr(current, field) for field in ALIAS_FIELDS})
    for field in ALIAS_FIELDS:
        value = getattr(overlay, field)
        if value is not None:
            setattr(result, field, value)
    for field in unset_fields:
        setattr(result, field, None)
    return result


def _alias_has_any_field(alias: AliasDef) -> bool:
    return any(getattr(alias, field) is not None for field in ALIAS_FIELDS)


def _handle_structured_chunk(
    channel: str,
    chunk: str,
    processor: StructuredStreamProcessor,
    forward_unknown_json: bool,
    stderr_filter: "_HumanStderrFilter",
    sanitize_osc: bool,
) -> None:
    if channel == "stderr":
        filtered = stderr_filter.feed(chunk)
        if filtered:
            print(
                _sanitize_human_output(filtered, sanitize_osc), end="", file=sys.stderr
            )
        return
    rendered = processor.feed(chunk)
    if rendered:
        print(_sanitize_human_output(rendered, sanitize_osc))
    if forward_unknown_json:
        for raw_line in processor.take_unknown_json_lines():
            print(raw_line, file=sys.stderr)


_KIMI_RESUME_RE = re.compile(
    r"^To resume this session: kimi -r [0-9a-f-]+\s*$", re.MULTILINE
)
_OSC_RE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
_OSC_8_PREFIX_RE = re.compile(r"^\x1b]8;")


def _filtered_human_stderr(stderr: str, runner_name: str) -> str:
    if runner_name.lower() not in {"k", "kimi"} or not stderr:
        return stderr
    filtered = _KIMI_RESUME_RE.sub("", stderr)
    filtered = filtered.strip("\n")
    return f"{filtered}\n" if filtered else ""


def _sanitize_raw_output(text: str, runner_name: str) -> str:
    if not text or runner_name.lower() not in {"oc", "opencode"}:
        return text
    return _OSC_RE.sub("", text)


def _sanitize_human_output(text: str, sanitize_osc: bool) -> str:
    if not text or not sanitize_osc:
        return text

    preserved: list[str] = []

    def _preserve_osc8(match: re.Match[str]) -> str:
        value = match.group(0)
        if _OSC_8_PREFIX_RE.match(value):
            preserved.append(value)
            return f"\0OSC8{len(preserved) - 1}\0"
        return ""

    sanitized = _OSC_RE.sub(_preserve_osc8, text)
    sanitized = sanitized.replace("\a", "")
    for index, value in enumerate(preserved):
        sanitized = sanitized.replace(f"\0OSC8{index}\0", value)
    return sanitized


def _print_cleanup_warnings(
    cleanup_session: bool,
    runner_name: str,
    spec: CommandSpec,
    result,
) -> None:
    if not cleanup_session:
        return
    runner_binary = spec.argv[0] if spec.argv else runner_name
    for warning in _cleanup_runner_session(
        runner_name=runner_name,
        runner_binary=runner_binary,
        stdout=result.stdout,
        stderr=result.stderr,
        env=spec.env,
    ):
        print(warning, file=sys.stderr)


def _session_persistence_pre_run_warnings(
    save_session: bool, cleanup_session: bool, runner_name: str
) -> list[str]:
    if save_session or cleanup_session:
        return []
    display = _canonical_session_runner_name(runner_name)
    if display not in {"opencode", "kimi", "crush", "roocode"}:
        return []
    return [
        f'warning: runner "{display}" may save this session; '
        "pass --save-session to allow this explicitly or --cleanup-session to try cleanup"
    ]


def _canonical_session_runner_name(runner_name: str) -> str:
    key = runner_name.lower()
    if key in {"oc", "opencode"}:
        return "opencode"
    if key in {"k", "kimi"}:
        return "kimi"
    if key in {"cr", "crush"}:
        return "crush"
    if key in {"rc", "roocode"}:
        return "roocode"
    return key


def _extract_opencode_session_id(stdout: str) -> str:
    for raw_line in stdout.splitlines():
        try:
            obj = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        session_id = obj.get("sessionID")
        if isinstance(session_id, str) and session_id:
            return session_id
    return ""


_KIMI_RESUME_ID_RE = re.compile(r"To resume this session: kimi -r ([0-9a-f-]+)")


def _extract_kimi_resume_session_id(stderr: str) -> str:
    match = _KIMI_RESUME_ID_RE.search(stderr)
    return match.group(1) if match else ""


def _cleanup_runner_session(
    *,
    runner_name: str,
    runner_binary: str,
    stdout: str,
    stderr: str,
    env: dict[str, str],
) -> list[str]:
    key = runner_name.lower()
    if key in {"oc", "opencode"}:
        return _cleanup_opencode_session(runner_binary, stdout)
    if key in {"k", "kimi"}:
        return _cleanup_kimi_session(stderr, env)
    return []


def _cleanup_opencode_session(runner_binary: str, stdout: str) -> list[str]:
    session_id = _extract_opencode_session_id(stdout)
    if not session_id:
        return ["warning: could not find OpenCode session ID for cleanup"]
    try:
        result = subprocess.run(
            [runner_binary, "session", "delete", session_id],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return [f"warning: failed to cleanup OpenCode session {session_id}: {exc}"]
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        suffix = f": {detail}" if detail else ""
        return [f"warning: failed to cleanup OpenCode session {session_id}{suffix}"]
    return []


def _cleanup_kimi_session(stderr: str, env: dict[str, str]) -> list[str]:
    session_id = _extract_kimi_resume_session_id(stderr)
    if not session_id:
        return ["warning: could not find Kimi session ID for cleanup"]
    root = Path(
        env.get("KIMI_SHARE_DIR")
        or os.environ.get("KIMI_SHARE_DIR")
        or Path.home() / ".kimi"
    )
    sessions_dir = root / "sessions"
    matches = list(sessions_dir.glob(f"**/{session_id}*"))
    if not matches:
        return [f"warning: could not find Kimi session file for cleanup: {session_id}"]
    warnings: list[str] = []
    for path in matches:
        try:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
        except OSError as exc:
            warnings.append(
                f"warning: failed to cleanup Kimi session {session_id}: {exc}"
            )
    return warnings


class _HumanStderrFilter:
    def __init__(self, runner_name: str) -> None:
        self._runner_name = runner_name
        self._buffer = ""

    def feed(self, chunk: str) -> str:
        self._buffer += chunk
        parts: list[str] = []
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            filtered = _filtered_human_stderr(f"{line}\n", self._runner_name)
            if filtered:
                parts.append(filtered)
        return "".join(parts)

    def finish(self) -> str:
        if not self._buffer:
            return ""
        filtered = _filtered_human_stderr(self._buffer, self._runner_name)
        self._buffer = ""
        return filtered


if __name__ == "__main__":
    raise SystemExit(main())

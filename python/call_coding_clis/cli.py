from __future__ import annotations

import os
import sys
import re

try:
    from .json_output import FormattedRenderer, StructuredStreamProcessor, parse_json_output, render_parsed
    from .runner import CommandSpec, Runner
    from .parser import (
        parse_args,
        resolve_command,
        resolve_output_plan,
        resolve_sanitize_osc,
        resolve_show_thinking,
    )
    from .config import load_config, render_example_config
    from .help import print_help, print_usage
except ImportError:
    from json_output import FormattedRenderer, StructuredStreamProcessor, parse_json_output, render_parsed
    from runner import CommandSpec, Runner
    from parser import (
        parse_args,
        resolve_command,
        resolve_output_plan,
        resolve_sanitize_osc,
        resolve_show_thinking,
    )
    from config import load_config, render_example_config
    from help import print_help, print_usage


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

    if not args or args == ["--help"] or args == ["-h"]:
        if not args:
            print_usage()
            return 1
        print_help()
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

    runner = Runner()
    show_thinking = resolve_show_thinking(parsed, config)
    sanitize_osc = resolve_sanitize_osc(parsed, config)
    forward_unknown_json = parsed.forward_unknown_json

    if output_plan.mode in {"text", "json"}:
        result = runner.run(spec)
        stdout = _sanitize_raw_output(result.stdout, output_plan.runner_name)
        stderr = _sanitize_raw_output(result.stderr, output_plan.runner_name)
        if stdout:
            print(stdout, end="")
        if stderr:
            print(stderr, end="", file=sys.stderr)
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
            tty=sys.stdout.isatty(),
        )
        if rendered:
            print(_sanitize_human_output(rendered, sanitize_osc))
        if forward_unknown_json:
            for raw_line in parsed_output.unknown_json_lines:
                print(raw_line, file=sys.stderr)
        return result.exit_code

    renderer = FormattedRenderer(
        show_thinking=show_thinking,
        tty=sys.stdout.isatty(),
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
        print(_sanitize_human_output(trailing_stderr, sanitize_osc), end="", file=sys.stderr)
    if forward_unknown_json:
        for raw_line in processor.take_unknown_json_lines():
            print(raw_line, file=sys.stderr)
    return result.exit_code


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
            print(_sanitize_human_output(filtered, sanitize_osc), end="", file=sys.stderr)
        return
    rendered = processor.feed(chunk)
    if rendered:
        print(_sanitize_human_output(rendered, sanitize_osc))
    if forward_unknown_json:
        for raw_line in processor.take_unknown_json_lines():
            print(raw_line, file=sys.stderr)


_KIMI_RESUME_RE = re.compile(r"^To resume this session: kimi -r [0-9a-f-]+\s*$", re.MULTILINE)
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

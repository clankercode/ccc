from __future__ import annotations

import os
import sys

try:
    from .runner import CommandSpec, Runner
    from .parser import parse_args, resolve_command
    from .config import load_config
    from .help import print_help, print_usage
except ImportError:
    from runner import CommandSpec, Runner
    from parser import parse_args, resolve_command
    from config import load_config
    from help import print_help, print_usage


def build_prompt_spec(prompt: str) -> CommandSpec:
    normalized_prompt = prompt.strip()
    if not normalized_prompt:
        raise ValueError("prompt must not be empty")
    return CommandSpec(argv=["opencode", "run", normalized_prompt])


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)

    if not args or args == ["--help"] or args == ["-h"]:
        if not args:
            print_usage()
            return 1
        print_help()
        return 0

    parsed = parse_args(args)
    if not parsed.prompt.strip():
        print("prompt must not be empty", file=sys.stderr)
        return 1
    config = load_config()
    try:
        argv_list, env_overrides, warnings = resolve_command(parsed, config)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    spec = CommandSpec(argv=argv_list, env=env_overrides)

    real_opencode = os.environ.get("CCC_REAL_OPENCODE", "")
    if real_opencode:
        spec.argv[0] = real_opencode

    for warning in warnings:
        print(warning, file=sys.stderr)

    result = Runner().run(spec)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())

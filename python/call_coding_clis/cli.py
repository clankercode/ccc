from __future__ import annotations

import os
import sys

try:
    from .runner import CommandSpec, Runner
    from .parser import parse_args, resolve_command
    from .config import load_config
except ImportError:
    from runner import CommandSpec, Runner
    from parser import parse_args, resolve_command
    from config import load_config


def build_prompt_spec(prompt: str) -> CommandSpec:
    normalized_prompt = prompt.strip()
    if not normalized_prompt:
        raise ValueError("prompt must not be empty")
    return CommandSpec(argv=["opencode", "run", normalized_prompt])


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)

    if not args:
        print(
            'usage: ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"',
            file=sys.stderr,
        )
        return 1

    if len(args) == 1:
        try:
            spec = build_prompt_spec(args[0])
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
    else:
        parsed = parse_args(args)
        if not parsed.prompt.strip():
            print("prompt must not be empty", file=sys.stderr)
            return 1
        config = load_config()
        try:
            argv_list, env_overrides = resolve_command(parsed, config)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        spec = CommandSpec(argv=argv_list, env=env_overrides)

    real_opencode = os.environ.get("CCC_REAL_OPENCODE", "")
    if real_opencode:
        spec.argv[0] = real_opencode

    result = Runner().run(spec)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())

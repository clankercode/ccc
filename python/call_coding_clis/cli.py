from __future__ import annotations

import sys

from .runner import CommandSpec, Runner


def build_prompt_spec(prompt: str) -> CommandSpec:
    normalized_prompt = prompt.strip()
    if not normalized_prompt:
        raise ValueError("prompt must not be empty")
    return CommandSpec(argv=["opencode", "run", normalized_prompt])


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print('usage: ccc "<Prompt>"', file=sys.stderr)
        return 1

    result = Runner().run(build_prompt_spec(args[0]))
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.exit_code

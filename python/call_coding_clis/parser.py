from __future__ import annotations

from dataclasses import dataclass, field
import re


RUNNER_REGISTRY: dict[str, RunnerInfo] = {}


@dataclass(slots=True)
class RunnerInfo:
    binary: str
    extra_args: list[str] = field(default_factory=list)
    thinking_flags: dict[int, list[str]] = field(default_factory=dict)
    provider_flag: str = ""
    model_flag: str = ""
    agent_flag: str = ""


@dataclass(slots=True)
class ParsedArgs:
    runner: str | None = None
    thinking: int | None = None
    provider: str | None = None
    model: str | None = None
    alias: str | None = None
    prompt: str = ""


@dataclass(slots=True)
class AliasDef:
    runner: str | None = None
    thinking: int | None = None
    provider: str | None = None
    model: str | None = None
    agent: str | None = None


@dataclass(slots=True)
class CccConfig:
    default_runner: str = "oc"
    default_provider: str = ""
    default_model: str = ""
    default_thinking: int | None = None
    aliases: dict[str, AliasDef] = field(default_factory=dict)
    abbreviations: dict[str, str] = field(default_factory=dict)


def _register_defaults() -> None:
    if RUNNER_REGISTRY:
        return
    RUNNER_REGISTRY["opencode"] = RunnerInfo(
        binary="opencode",
        extra_args=["run"],
        thinking_flags={},
        provider_flag="",
        model_flag="",
        agent_flag="--agent",
    )
    RUNNER_REGISTRY["claude"] = RunnerInfo(
        binary="claude",
        extra_args=[],
        thinking_flags={
            0: ["--no-thinking"],
            1: ["--thinking", "low"],
            2: ["--thinking", "medium"],
            3: ["--thinking", "high"],
            4: ["--thinking", "max"],
        },
        provider_flag="",
        model_flag="--model",
        agent_flag="--agent",
    )
    RUNNER_REGISTRY["kimi"] = RunnerInfo(
        binary="kimi",
        extra_args=[],
        thinking_flags={
            0: ["--no-think"],
            1: ["--think", "low"],
            2: ["--think", "medium"],
            3: ["--think", "high"],
            4: ["--think", "max"],
        },
        provider_flag="",
        model_flag="--model",
        agent_flag="--agent",
    )
    RUNNER_REGISTRY["codex"] = RunnerInfo(
        binary="codex",
        extra_args=[],
        thinking_flags={},
        provider_flag="",
        model_flag="--model",
    )
    RUNNER_REGISTRY["crush"] = RunnerInfo(
        binary="crush",
        extra_args=[],
        thinking_flags={},
        provider_flag="",
        model_flag="",
    )

    RUNNER_REGISTRY["oc"] = RUNNER_REGISTRY["opencode"]
    RUNNER_REGISTRY["cc"] = RUNNER_REGISTRY["claude"]
    RUNNER_REGISTRY["c"] = RUNNER_REGISTRY["claude"]
    RUNNER_REGISTRY["k"] = RUNNER_REGISTRY["kimi"]
    RUNNER_REGISTRY["rc"] = RUNNER_REGISTRY["codex"]
    RUNNER_REGISTRY["cr"] = RUNNER_REGISTRY["crush"]


_register_defaults()

RUNNER_SELECTOR_RE = re.compile(
    r"^(?:oc|cc|c|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$", re.IGNORECASE
)
THINKING_RE = re.compile(
    r"^\+(0|1|2|3|4|none|low|med|mid|medium|high|max|xhigh)$",
    re.IGNORECASE,
)
PROVIDER_MODEL_RE = re.compile(r"^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$")
MODEL_RE = re.compile(r"^:([a-zA-Z0-9._-]+)$")
ALIAS_RE = re.compile(r"^@([a-zA-Z0-9_-]+)$")

THINKING_TOKEN_TO_LEVEL = {
    "0": 0,
    "none": 0,
    "1": 1,
    "low": 1,
    "2": 2,
    "med": 2,
    "mid": 2,
    "medium": 2,
    "3": 3,
    "high": 3,
    "4": 4,
    "max": 4,
    "xhigh": 4,
}


def parse_args(argv: list[str]) -> ParsedArgs:
    parsed = ParsedArgs()
    positional: list[str] = []

    for token in argv:
        if RUNNER_SELECTOR_RE.match(token) and parsed.runner is None and not positional:
            parsed.runner = token.lower()
        elif THINKING_RE.match(token) and not positional:
            parsed.thinking = THINKING_TOKEN_TO_LEVEL[
                THINKING_RE.match(token).group(1).lower()
            ]
        elif PROVIDER_MODEL_RE.match(token) and not positional:
            m = PROVIDER_MODEL_RE.match(token)
            parsed.provider = m.group(1)
            parsed.model = m.group(2)
        elif MODEL_RE.match(token) and not positional:
            m = MODEL_RE.match(token)
            parsed.model = m.group(1)
        elif ALIAS_RE.match(token) and parsed.alias is None and not positional:
            parsed.alias = ALIAS_RE.match(token).group(1)
        else:
            positional.append(token)

    parsed.prompt = " ".join(positional)
    return parsed


def resolve_runner_name(name: str | None, config: CccConfig) -> str:
    if name is None:
        return config.default_runner
    abbrev = config.abbreviations.get(name)
    if abbrev:
        return abbrev
    return name


def resolve_command(
    parsed: ParsedArgs,
    config: CccConfig | None = None,
) -> tuple[list[str], dict[str, str], list[str]]:
    if config is None:
        config = CccConfig()

    runner_name = resolve_runner_name(parsed.runner, config)
    info = RUNNER_REGISTRY.get(
        runner_name,
        RUNNER_REGISTRY.get(config.default_runner, RUNNER_REGISTRY["opencode"]),
    )

    warnings: list[str] = []
    alias_def = None
    if parsed.alias and parsed.alias in config.aliases:
        alias_def = config.aliases[parsed.alias]
    requested_agent = parsed.alias if parsed.alias and alias_def is None else None

    effective_runner_name = runner_name
    if alias_def and alias_def.runner and parsed.runner is None:
        effective_runner_name = resolve_runner_name(alias_def.runner, config)
        info = RUNNER_REGISTRY.get(effective_runner_name, info)

    argv = [info.binary] + list(info.extra_args)

    effective_thinking = parsed.thinking
    if effective_thinking is None and alias_def and alias_def.thinking is not None:
        effective_thinking = alias_def.thinking
    if effective_thinking is None:
        effective_thinking = config.default_thinking
    if effective_thinking is not None and effective_thinking in info.thinking_flags:
        argv.extend(info.thinking_flags[effective_thinking])

    effective_provider = parsed.provider
    if effective_provider is None and alias_def and alias_def.provider:
        effective_provider = alias_def.provider
    if effective_provider is None:
        effective_provider = config.default_provider

    effective_model = parsed.model
    if effective_model is None and alias_def and alias_def.model:
        effective_model = alias_def.model
    if effective_model is None:
        effective_model = config.default_model

    if effective_model and info.model_flag:
        argv.extend([info.model_flag, effective_model])

    effective_agent = requested_agent
    if effective_agent is None and alias_def and alias_def.agent:
        effective_agent = alias_def.agent
    if effective_agent:
        if info.agent_flag:
            argv.extend([info.agent_flag, effective_agent])
        else:
            warnings.append(
                f'warning: runner "{effective_runner_name}" does not support agents; '
                f'ignoring @{effective_agent}'
            )

    env_overrides: dict[str, str] = {}
    if effective_provider:
        env_overrides["CCC_PROVIDER"] = effective_provider

    prompt = parsed.prompt.strip()
    if not prompt:
        raise ValueError("prompt must not be empty")

    argv.append(prompt)
    return argv, env_overrides, warnings

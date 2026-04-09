from __future__ import annotations

from dataclasses import dataclass, field
import re


RUNNER_REGISTRY: dict[str, RunnerInfo] = {}
PERMISSION_MODES = {"safe", "auto", "yolo", "plan"}


@dataclass(slots=True)
class RunnerInfo:
    binary: str
    extra_args: list[str] = field(default_factory=list)
    thinking_flags: dict[int, list[str]] = field(default_factory=dict)
    show_thinking_flags: dict[bool, list[str]] = field(default_factory=dict)
    yolo_flags: list[str] = field(default_factory=list)
    provider_flag: str = ""
    model_flag: str = ""
    agent_flag: str = ""
    prompt_flag: str = ""


@dataclass(slots=True)
class ParsedArgs:
    runner: str | None = None
    thinking: int | None = None
    show_thinking: bool | None = None
    print_config: bool = False
    sanitize_osc: bool | None = None
    output_mode: str | None = None
    forward_unknown_json: bool = False
    yolo: bool = False
    permission_mode: str | None = None
    provider: str | None = None
    model: str | None = None
    alias: str | None = None
    prompt: str = ""


@dataclass(slots=True)
class AliasDef:
    runner: str | None = None
    thinking: int | None = None
    show_thinking: bool | None = None
    sanitize_osc: bool | None = None
    output_mode: str | None = None
    provider: str | None = None
    model: str | None = None
    agent: str | None = None
    prompt: str | None = None


@dataclass(slots=True)
class CccConfig:
    default_runner: str = "oc"
    default_provider: str = ""
    default_model: str = ""
    default_thinking: int | None = None
    default_show_thinking: bool = False
    default_sanitize_osc: bool | None = None
    default_output_mode: str = "text"
    aliases: dict[str, AliasDef] = field(default_factory=dict)
    abbreviations: dict[str, str] = field(default_factory=dict)


def _register_defaults() -> None:
    if RUNNER_REGISTRY:
        return
    RUNNER_REGISTRY["opencode"] = RunnerInfo(
        binary="opencode",
        extra_args=["run"],
        thinking_flags={},
        show_thinking_flags={True: ["--thinking"]},
        yolo_flags=[],
        provider_flag="",
        model_flag="",
        agent_flag="--agent",
        prompt_flag="",
    )
    RUNNER_REGISTRY["claude"] = RunnerInfo(
        binary="claude",
        extra_args=["-p"],
        thinking_flags={
            0: ["--thinking", "disabled"],
            1: ["--thinking", "enabled", "--effort", "low"],
            2: ["--thinking", "enabled", "--effort", "medium"],
            3: ["--thinking", "enabled", "--effort", "high"],
            4: ["--thinking", "enabled", "--effort", "max"],
        },
        show_thinking_flags={True: ["--thinking", "enabled", "--effort", "low"]},
        yolo_flags=["--dangerously-skip-permissions"],
        provider_flag="",
        model_flag="--model",
        agent_flag="--agent",
        prompt_flag="",
    )
    RUNNER_REGISTRY["kimi"] = RunnerInfo(
        binary="kimi",
        extra_args=[],
        thinking_flags={
            0: ["--no-thinking"],
            1: ["--thinking"],
            2: ["--thinking"],
            3: ["--thinking"],
            4: ["--thinking"],
        },
        show_thinking_flags={True: ["--thinking"]},
        yolo_flags=["--yolo"],
        provider_flag="",
        model_flag="--model",
        agent_flag="--agent",
        prompt_flag="--prompt",
    )
    RUNNER_REGISTRY["codex"] = RunnerInfo(
        binary="codex",
        extra_args=["exec"],
        thinking_flags={},
        show_thinking_flags={},
        yolo_flags=["--dangerously-bypass-approvals-and-sandbox"],
        provider_flag="",
        model_flag="--model",
        prompt_flag="",
    )
    RUNNER_REGISTRY["roocode"] = RunnerInfo(
        binary="roocode",
        extra_args=[],
        thinking_flags={},
        show_thinking_flags={},
        provider_flag="",
        model_flag="",
        prompt_flag="",
    )
    RUNNER_REGISTRY["crush"] = RunnerInfo(
        binary="crush",
        extra_args=["run"],
        thinking_flags={},
        show_thinking_flags={},
        yolo_flags=[],
        provider_flag="",
        model_flag="",
        prompt_flag="",
    )

    RUNNER_REGISTRY["oc"] = RUNNER_REGISTRY["opencode"]
    RUNNER_REGISTRY["cc"] = RUNNER_REGISTRY["claude"]
    RUNNER_REGISTRY["c"] = RUNNER_REGISTRY["codex"]
    RUNNER_REGISTRY["cx"] = RUNNER_REGISTRY["codex"]
    RUNNER_REGISTRY["k"] = RUNNER_REGISTRY["kimi"]
    RUNNER_REGISTRY["rc"] = RUNNER_REGISTRY["roocode"]
    RUNNER_REGISTRY["cr"] = RUNNER_REGISTRY["crush"]


_register_defaults()

RUNNER_SELECTOR_RE = re.compile(
    r"^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$", re.IGNORECASE
)
THINKING_RE = re.compile(
    r"^\+(0|1|2|3|4|none|low|med|mid|medium|high|max|xhigh)$",
    re.IGNORECASE,
)
PROVIDER_MODEL_RE = re.compile(r"^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$")
MODEL_RE = re.compile(r"^:([a-zA-Z0-9._-]+)$")
ALIAS_RE = re.compile(r"^@([a-zA-Z0-9_-]+)$")
OUTPUT_MODE_RE = re.compile(
    r"^(text|stream-text|json|stream-json|formatted|stream-formatted)$",
    re.IGNORECASE,
)

OUTPUT_MODE_SUGAR = {
    ".text": "text",
    "..text": "stream-text",
    ".json": "json",
    "..json": "stream-json",
    ".fmt": "formatted",
    "..fmt": "stream-formatted",
}

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
    force_prompt = False
    index = 0

    while index < len(argv):
        token = argv[index]
        if force_prompt or positional:
            positional.append(token)
            index += 1
            continue
        if token == "--":
            force_prompt = True
            index += 1
            continue
        if RUNNER_SELECTOR_RE.match(token):
            parsed.runner = token.lower()
        elif THINKING_RE.match(token):
            parsed.thinking = THINKING_TOKEN_TO_LEVEL[
                THINKING_RE.match(token).group(1).lower()
            ]
        elif token in {"--show-thinking", "--no-show-thinking"}:
            parsed.show_thinking = token == "--show-thinking"
        elif token == "--print-config":
            parsed.print_config = True
        elif token in {"--sanitize-osc", "--no-sanitize-osc"}:
            parsed.sanitize_osc = token == "--sanitize-osc"
        elif token in {"--output-mode", "-o"}:
            if index + 1 >= len(argv):
                parsed.output_mode = ""
            else:
                parsed.output_mode = argv[index + 1].lower()
                index += 1
        elif token == "--forward-unknown-json":
            parsed.forward_unknown_json = True
        elif token.lower() in OUTPUT_MODE_SUGAR:
            parsed.output_mode = OUTPUT_MODE_SUGAR[token.lower()]
        elif token in {"--yolo", "-y"}:
            parsed.yolo = True
            parsed.permission_mode = "yolo"
        elif token == "--permission-mode":
            if index + 1 >= len(argv):
                parsed.permission_mode = ""
            else:
                parsed.permission_mode = argv[index + 1].lower()
                parsed.yolo = parsed.permission_mode == "yolo"
                index += 1
        elif PROVIDER_MODEL_RE.match(token):
            m = PROVIDER_MODEL_RE.match(token)
            parsed.provider = m.group(1)
            parsed.model = m.group(2)
        elif MODEL_RE.match(token):
            m = MODEL_RE.match(token)
            parsed.model = m.group(1)
        elif ALIAS_RE.match(token):
            parsed.alias = ALIAS_RE.match(token).group(1)
        else:
            positional.append(token)
        index += 1

    parsed.prompt = " ".join(positional)
    return parsed


def resolve_runner_name(name: str | None, config: CccConfig) -> str:
    if name is None:
        return config.default_runner
    abbrev = config.abbreviations.get(name)
    if abbrev:
        return abbrev
    return name


def _resolve_alias_def(parsed: ParsedArgs, config: CccConfig) -> AliasDef | None:
    if parsed.alias and parsed.alias in config.aliases:
        return config.aliases[parsed.alias]
    return None


def resolve_effective_runner(
    parsed: ParsedArgs, config: CccConfig
) -> tuple[str, RunnerInfo, AliasDef | None]:
    runner_name = resolve_runner_name(parsed.runner, config)
    info = RUNNER_REGISTRY.get(
        runner_name,
        RUNNER_REGISTRY.get(config.default_runner, RUNNER_REGISTRY["opencode"]),
    )
    alias_def = _resolve_alias_def(parsed, config)

    effective_runner_name = runner_name
    if alias_def and alias_def.runner and parsed.runner is None:
        effective_runner_name = resolve_runner_name(alias_def.runner, config)
        info = RUNNER_REGISTRY.get(effective_runner_name, info)
    return effective_runner_name, info, alias_def


def _supported_output_modes(effective_runner_name: str) -> set[str]:
    key = effective_runner_name.lower()
    if key in {"cc", "claude"}:
        return {
            "text",
            "stream-text",
            "json",
            "stream-json",
            "formatted",
            "stream-formatted",
        }
    if key in {"k", "kimi"}:
        return {"text", "stream-text", "stream-json", "formatted", "stream-formatted"}
    if key in {"oc", "opencode"}:
        return {"text", "stream-text", "json", "formatted"}
    return {"text", "stream-text"}


def resolve_output_mode(parsed: ParsedArgs, config: CccConfig | None = None) -> str:
    if config is None:
        config = CccConfig()
    _, _, alias_def = resolve_effective_runner(parsed, config)
    mode = parsed.output_mode
    if mode is None and alias_def and alias_def.output_mode:
        mode = alias_def.output_mode
    if mode is None:
        mode = config.default_output_mode
    if mode == "":
        raise ValueError(
            "output mode requires one of: text, stream-text, json, stream-json, formatted, stream-formatted"
        )
    mode = mode.lower()
    if not OUTPUT_MODE_RE.match(mode):
        raise ValueError(
            "output mode must be one of: text, stream-text, json, stream-json, formatted, stream-formatted"
        )
    return mode


def resolve_show_thinking(parsed: ParsedArgs, config: CccConfig | None = None) -> bool:
    if config is None:
        config = CccConfig()
    _, _, alias_def = resolve_effective_runner(parsed, config)
    value = parsed.show_thinking
    if value is None and alias_def and alias_def.show_thinking is not None:
        value = alias_def.show_thinking
    if value is None:
        value = config.default_show_thinking
    return bool(value)


def resolve_sanitize_osc(parsed: ParsedArgs, config: CccConfig | None = None) -> bool:
    if config is None:
        config = CccConfig()
    _, _, alias_def = resolve_effective_runner(parsed, config)
    value = parsed.sanitize_osc
    if value is None and alias_def and alias_def.sanitize_osc is not None:
        value = alias_def.sanitize_osc
    if value is None:
        value = config.default_sanitize_osc
    if value is None:
        value = "formatted" in resolve_output_mode(parsed, config)
    return bool(value)


@dataclass(slots=True)
class OutputPlan:
    runner_name: str
    mode: str
    stream: bool
    formatted: bool
    schema: str | None
    argv_flags: list[str]


def resolve_output_plan(parsed: ParsedArgs, config: CccConfig | None = None) -> OutputPlan:
    if config is None:
        config = CccConfig()
    effective_runner_name, _, _ = resolve_effective_runner(parsed, config)
    mode = resolve_output_mode(parsed, config)
    supported = _supported_output_modes(effective_runner_name)
    if mode not in supported:
        raise ValueError(
            f'runner "{effective_runner_name}" does not support output mode "{mode}"'
        )

    key = effective_runner_name.lower()
    if mode in {"text", "stream-text"}:
        return OutputPlan(
            runner_name=effective_runner_name,
            mode=mode,
            stream=mode.startswith("stream-"),
            formatted=False,
            schema=None,
            argv_flags=[],
        )
    if key in {"cc", "claude"}:
        flags = (
            ["--output-format", "json"]
            if mode == "json"
            else ["--verbose", "--output-format", "stream-json"]
        )
        if mode == "stream-formatted":
            flags.append("--include-partial-messages")
        return OutputPlan(
            runner_name=effective_runner_name,
            mode=mode,
            stream=mode.startswith("stream-"),
            formatted="formatted" in mode,
            schema="claude-code",
            argv_flags=flags,
        )
    if key in {"k", "kimi"}:
        return OutputPlan(
            runner_name=effective_runner_name,
            mode=mode,
            stream=mode.startswith("stream-"),
            formatted="formatted" in mode,
            schema="kimi",
            argv_flags=["--print", "--output-format", "stream-json"],
        )
    if key in {"oc", "opencode"}:
        return OutputPlan(
            runner_name=effective_runner_name,
            mode=mode,
            stream=False,
            formatted=mode == "formatted",
            schema="opencode",
            argv_flags=["--format", "json"],
        )
    return OutputPlan(
        runner_name=effective_runner_name,
        mode=mode,
        stream=mode.startswith("stream-"),
        formatted=False,
        schema=None,
        argv_flags=[],
    )


def resolve_command(
    parsed: ParsedArgs,
    config: CccConfig | None = None,
) -> tuple[list[str], dict[str, str], list[str]]:
    if config is None:
        config = CccConfig()

    effective_runner_name, info, alias_def = resolve_effective_runner(parsed, config)

    warnings: list[str] = []
    requested_agent = parsed.alias if parsed.alias and alias_def is None else None

    argv = [info.binary] + list(info.extra_args)
    output_plan = resolve_output_plan(parsed, config)
    argv.extend(output_plan.argv_flags)

    effective_thinking = parsed.thinking
    if effective_thinking is None and alias_def and alias_def.thinking is not None:
        effective_thinking = alias_def.thinking
    if effective_thinking is None:
        effective_thinking = config.default_thinking
    if effective_thinking is not None and effective_thinking in info.thinking_flags:
        argv.extend(info.thinking_flags[effective_thinking])

    effective_show_thinking = parsed.show_thinking
    if effective_show_thinking is None and alias_def and alias_def.show_thinking is not None:
        effective_show_thinking = alias_def.show_thinking
    if effective_show_thinking is None:
        effective_show_thinking = config.default_show_thinking
    if effective_thinking is None and effective_show_thinking:
        if True in info.show_thinking_flags:
            argv.extend(info.show_thinking_flags[True])

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

    env_overrides: dict[str, str] = {}
    if effective_provider:
        env_overrides["CCC_PROVIDER"] = effective_provider
    if effective_runner_name in {"oc", "opencode"}:
        env_overrides["OPENCODE_DISABLE_TERMINAL_TITLE"] = "true"

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

    effective_permission_mode = (
        parsed.permission_mode if parsed.permission_mode is not None else ("yolo" if parsed.yolo else None)
    )
    if effective_permission_mode == "":
        raise ValueError("permission mode requires one of: safe, auto, yolo, plan")
    if effective_permission_mode is not None and effective_permission_mode not in PERMISSION_MODES:
        raise ValueError("permission mode must be one of: safe, auto, yolo, plan")

    if effective_permission_mode == "safe":
        if effective_runner_name in {"cc", "claude"}:
            argv.extend(["--permission-mode", "default"])
    elif effective_permission_mode == "auto":
        if effective_runner_name in {"cc", "claude"}:
            argv.extend(["--permission-mode", "auto"])
        elif effective_runner_name in {"c", "cx", "codex"}:
            argv.append("--full-auto")
        else:
            warnings.append(
                f'warning: runner "{effective_runner_name}" does not support permission mode "auto"; ignoring it'
            )
    elif effective_permission_mode == "yolo":
        if info.yolo_flags:
            argv.extend(info.yolo_flags)
        elif effective_runner_name in {"oc", "opencode"}:
            env_overrides["OPENCODE_CONFIG_CONTENT"] = '{"permission":"allow"}'
        elif effective_runner_name in {"cr", "crush"}:
            warnings.append(
                'warning: runner "crush" does not support yolo mode in non-interactive run mode; ignoring --yolo'
            )
        elif effective_runner_name in {"rc", "roocode"}:
            warnings.append(
                'warning: runner "roocode" yolo mode is unverified; ignoring --yolo'
            )
    elif effective_permission_mode == "plan":
        if effective_runner_name in {"cc", "claude"}:
            argv.extend(["--permission-mode", "plan"])
        elif effective_runner_name in {"k", "kimi"}:
            argv.append("--plan")
        else:
            warnings.append(
                f'warning: runner "{effective_runner_name}" does not support permission mode "plan"; ignoring it'
            )

    prompt = parsed.prompt.strip()
    if not prompt and alias_def and alias_def.prompt is not None:
        prompt = str(alias_def.prompt).strip()
    if not prompt:
        raise ValueError("prompt must not be empty")

    if info.prompt_flag:
        argv.extend([info.prompt_flag, prompt])
    else:
        argv.append(prompt)
    return argv, env_overrides, warnings

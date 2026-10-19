"""Decide when a preset may retry on another model.

Fallbacks are model substitutions on the same runner. They run only after a
capacity or overload failure that produced no assistant output. Authentication
failures, timeouts, and any assistant output keep the original result.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

try:
    from .parser import CccConfig, ParsedArgs, resolve_effective_runner
except ImportError:
    from parser import CccConfig, ParsedArgs, resolve_effective_runner


_AUTH_RE = re.compile(
    r"authentication_error|no usable account credential|needs reauthentication|"
    r"unauthorized|invalid api key|invalid_api_key|not logged in|please run /login|"
    r"\b401\b",
    re.IGNORECASE,
)
_CAPACITY_RE = re.compile(
    r"at capacity|server_overloaded|overloaded_error|model is overloaded|"
    r"model overloaded|\boverloaded\b",
    re.IGNORECASE,
)
_NON_OUTPUT_EVENT_TYPES = {
    "error",
    "turn.failed",
    "thread.started",
    "turn.started",
}
_NON_OUTPUT_ITEM_TYPES = {"error", "warning"}


@dataclass(slots=True)
class ModelFallbackPlan:
    """models[0] is the attempt already present in the planned argv."""

    models: list[str]
    announce: bool = False
    pre_notices: list[str] = field(default_factory=list)


def is_disallowed_fallback_model(model: str) -> bool:
    lowered = model.lower()
    return "minimax" in lowered or "claude" in lowered


def is_disallowed_fallback_runner(runner_name: str) -> bool:
    return runner_name.lower() in {"cc", "claude"}


def is_auth_failure(stdout: str, stderr: str) -> bool:
    return _AUTH_RE.search(f"{stdout}\n{stderr}") is not None


def is_capacity_failure(stdout: str, stderr: str) -> bool:
    return _CAPACITY_RE.search(f"{stdout}\n{stderr}") is not None


def _json_line_is_non_output(line: str) -> bool | None:
    """True when a JSON event is not assistant output. None when it is not JSON."""
    if not line.startswith("{"):
        return None
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(value, dict):
        return None
    event_type = str(value.get("type") or "")
    if event_type in _NON_OUTPUT_EVENT_TYPES:
        return True
    if event_type == "item.completed":
        item = value.get("item")
        item_type = ""
        if isinstance(item, dict):
            item_type = str(item.get("type") or "")
        return item_type in _NON_OUTPUT_ITEM_TYPES
    if not event_type:
        return None
    return False


def assistant_output_started(stdout: str) -> bool:
    """True when stdout contains assistant work, not only an error event."""
    saw_line = False
    for raw_line in stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        saw_line = True
        non_output = _json_line_is_non_output(line)
        if non_output is None or non_output is False:
            return True
    return False if saw_line else bool(stdout.strip())


def failure_allows_fallback(
    exit_code: int, timed_out: bool, stdout: str, stderr: str
) -> bool:
    if timed_out or exit_code == 0:
        return False
    if assistant_output_started(stdout):
        return False
    if is_auth_failure(stdout, stderr):
        return False
    return is_capacity_failure(stdout, stderr)


def terminal_notice(
    label: str, exit_code: int, timed_out: bool, stdout: str, stderr: str
) -> str:
    if exit_code == 0 and not timed_out:
        return f"ccc: ran model {label}\n"
    if assistant_output_started(stdout):
        return f"ccc: model {label} failed after producing output; not falling back\n"
    if is_auth_failure(stdout, stderr):
        return f"ccc: model {label} failed with an authentication error; not falling back\n"
    if is_capacity_failure(stdout, stderr):
        return f"ccc: model {label} failed with a capacity error; no fallback models left\n"
    return f"ccc: model {label} failed; not falling back\n"


def trying_notice(current: str, nxt: str) -> str:
    return (
        f"ccc: model {current} is at capacity before producing output; trying {nxt}\n"
    )


def argv_with_model(argv: list[str], model: str, runner_name: str) -> list[str]:
    updated = list(argv)
    if "--model" in updated:
        index = updated.index("--model")
        if index + 1 < len(updated):
            current = updated[index + 1]
            if (
                runner_name in {"oc", "opencode"}
                and "/" in current
                and "/" not in model
            ):
                provider = current.split("/", 1)[0]
                updated[index + 1] = f"{provider}/{model}"
            else:
                updated[index + 1] = model
            return updated
    if updated:
        return [*updated[:-1], "--model", model, updated[-1]]
    return ["--model", model]


def _effective_model_label(parsed: ParsedArgs, config: CccConfig, alias) -> str:
    if parsed.model:
        return parsed.model
    if alias is not None and alias.model:
        return alias.model
    if config.default_model:
        return config.default_model
    return "(default)"


class ModelFallbackCursor:
    def __init__(self, plan: ModelFallbackPlan) -> None:
        self.plan = plan
        self.index = 0

    def retry_notice(
        self, exit_code: int, timed_out: bool, stdout: str, stderr: str
    ) -> str | None:
        if self.index + 1 >= len(self.plan.models):
            return None
        if not failure_allows_fallback(exit_code, timed_out, stdout, stderr):
            return None
        current = self.plan.models[self.index]
        self.index += 1
        return trying_notice(current, self.plan.models[self.index])

    def current_label(self) -> str:
        return self.plan.models[self.index]


def plan_model_fallback(parsed: ParsedArgs, config: CccConfig) -> ModelFallbackPlan:
    runner_name, _info, alias = resolve_effective_runner(parsed, config)
    configured = list(alias.fallback_models or []) if alias is not None else []
    primary = _effective_model_label(parsed, config, alias)
    if not configured:
        return ModelFallbackPlan(models=[primary])
    if is_disallowed_fallback_runner(runner_name):
        return ModelFallbackPlan(
            models=[primary],
            pre_notices=[
                f"ccc: ignoring fallback_models for runner {runner_name}\n"
            ],
        )
    models = [primary]
    notices: list[str] = []
    for model in configured:
        if is_disallowed_fallback_model(model):
            notices.append(
                "ccc: skipping fallback model "
                f"{model}; MiniMax and Claude models are not fallback targets\n"
            )
            continue
        if model in models:
            continue
        models.append(model)
    return ModelFallbackPlan(
        models=models,
        announce=True,
        pre_notices=notices,
    )

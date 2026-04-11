from __future__ import annotations

from dataclasses import dataclass, field
import json
from typing import Any


RESET = "\x1b[0m"


@dataclass(slots=True)
class TextContent:
    text: str


@dataclass(slots=True)
class ThinkingContent:
    thinking: str


@dataclass(slots=True)
class ToolCall:
    id: str
    name: str
    arguments: str


@dataclass(slots=True)
class ToolResult:
    tool_call_id: str
    content: str
    is_error: bool = False


@dataclass(slots=True)
class JsonEvent:
    event_type: str
    text: str = ""
    thinking: str = ""
    tool_call: ToolCall | None = None
    tool_result: ToolResult | None = None
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class ParsedJsonOutput:
    schema_name: str
    events: list[JsonEvent] = field(default_factory=list)
    final_text: str = ""
    session_id: str = ""
    error: str = ""
    usage: dict[str, int] = field(default_factory=dict)
    cost_usd: float = 0.0
    duration_ms: int = 0
    raw_lines: list[dict[str, Any]] = field(default_factory=list)
    unknown_json_lines: list[str] = field(default_factory=list)


def _new_output(schema_name: str) -> ParsedJsonOutput:
    return ParsedJsonOutput(schema_name=schema_name)


def _parse_json_line(line: str) -> tuple[dict[str, Any] | None, str]:
    raw_line = line.strip()
    if not raw_line:
        return None, raw_line
    try:
        obj = json.loads(raw_line)
    except json.JSONDecodeError:
        return None, raw_line
    if not isinstance(obj, dict):
        return None, raw_line
    return obj, raw_line


def _apply_opencode_obj(result: ParsedJsonOutput, obj: dict[str, Any]) -> bool:
    result.raw_lines.append(obj)
    if "response" in obj:
        text = str(obj["response"])
        result.final_text = text
        result.events.append(JsonEvent(event_type="text", text=text, raw=obj))
        return True
    if "error" in obj:
        result.error = str(obj["error"])
        result.events.append(JsonEvent(event_type="error", text=result.error, raw=obj))
        return True
    event_type = str(obj.get("type", ""))
    if event_type == "step_start":
        result.session_id = str(obj.get("sessionID", result.session_id))
        return True
    if event_type == "text":
        part = obj.get("part", {})
        if isinstance(part, dict):
            text = str(part.get("text", ""))
            if text:
                result.final_text = text
                result.events.append(JsonEvent(event_type="text", text=text, raw=obj))
        return True
    if event_type == "tool_use":
        part = obj.get("part", {})
        if not isinstance(part, dict):
            return False
        tool_name = str(part.get("tool", ""))
        call_id = str(part.get("callID", ""))
        state = part.get("state", {})
        if not isinstance(state, dict):
            state = {}
        tool_input = state.get("input", {})
        tool_output = state.get("output", "")
        result.events.append(
            JsonEvent(
                event_type="tool_use",
                tool_call=ToolCall(
                    id=call_id,
                    name=tool_name,
                    arguments=json.dumps(tool_input)
                    if isinstance(tool_input, dict)
                    else "",
                ),
                raw=obj,
            )
        )
        result.events.append(
            JsonEvent(
                event_type="tool_result",
                tool_result=ToolResult(
                    tool_call_id=call_id,
                    content=str(tool_output),
                    is_error=str(state.get("status", "")).lower() == "error",
                ),
                raw=obj,
            )
        )
        return True
    if event_type == "step_finish":
        part = obj.get("part", {})
        if isinstance(part, dict):
            tokens = part.get("tokens", {})
            if isinstance(tokens, dict):
                usage: dict[str, int] = {}
                for key in ("total", "input", "output", "reasoning"):
                    value = tokens.get(key)
                    if isinstance(value, int):
                        usage[key] = value
                cache = tokens.get("cache", {})
                if isinstance(cache, dict):
                    for key in ("write", "read"):
                        value = cache.get(key)
                        if isinstance(value, int):
                            usage[f"cache_{key}"] = value
                if usage:
                    result.usage = usage
            cost = part.get("cost")
            if isinstance(cost, (int, float)):
                result.cost_usd = float(cost)
        return True
    return False


def _apply_claude_obj(result: ParsedJsonOutput, obj: dict[str, Any]) -> bool:
    result.raw_lines.append(obj)
    msg_type = str(obj.get("type", ""))

    if msg_type == "system":
        subtype = str(obj.get("subtype", ""))
        if subtype == "init":
            result.session_id = str(obj.get("session_id", ""))
        elif subtype == "api_retry":
            result.events.append(JsonEvent(event_type="system_retry", raw=obj))
        return subtype in {"init", "api_retry"}

    if msg_type == "assistant":
        message = obj.get("message", {})
        if isinstance(message, dict):
            content = message.get("content", [])
            texts: list[str] = []
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        texts.append(str(block.get("text", "")))
            if texts:
                text = "\n".join(texts)
                result.final_text = text
                result.events.append(
                    JsonEvent(event_type="assistant", text=text, raw=obj)
                )
            usage = message.get("usage", {})
            if isinstance(usage, dict):
                result.usage = {
                    str(k): int(v) for k, v in usage.items() if isinstance(v, int)
                }
        return True

    if msg_type == "user":
        message = obj.get("message", {})
        if isinstance(message, dict):
            content = message.get("content", [])
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        result.events.append(
                            JsonEvent(
                                event_type="tool_result",
                                tool_result=ToolResult(
                                    tool_call_id=str(block.get("tool_use_id", "")),
                                    content=str(block.get("content", "")),
                                    is_error=bool(block.get("is_error", False)),
                                ),
                                raw=obj,
                            )
                        )
        return (
            any(
                isinstance(block, dict) and block.get("type") == "tool_result"
                for block in content
            )
            if isinstance(content, list)
            else False
        )

    if msg_type == "stream_event":
        event = obj.get("event", {})
        if not isinstance(event, dict):
            return
        event_type = str(event.get("type", ""))
        if event_type == "content_block_delta":
            delta = event.get("delta", {})
            if not isinstance(delta, dict):
                return
            delta_type = str(delta.get("type", ""))
            if delta_type == "text_delta":
                result.events.append(
                    JsonEvent(
                        event_type="text_delta",
                        text=str(delta.get("text", "")),
                        raw=obj,
                    )
                )
                return True
            elif delta_type == "thinking_delta":
                result.events.append(
                    JsonEvent(
                        event_type="thinking_delta",
                        thinking=str(delta.get("thinking", "")),
                        raw=obj,
                    )
                )
                return True
            elif delta_type == "input_json_delta":
                result.events.append(
                    JsonEvent(
                        event_type="tool_input_delta",
                        text=str(delta.get("partial_json", "")),
                        raw=obj,
                    )
                )
                return True
        elif event_type == "content_block_start":
            content_block = event.get("content_block", {})
            if not isinstance(content_block, dict):
                return
            block_type = str(content_block.get("type", ""))
            if block_type == "thinking":
                result.events.append(JsonEvent(event_type="thinking_start", raw=obj))
                return True
            elif block_type == "tool_use":
                result.events.append(
                    JsonEvent(
                        event_type="tool_use_start",
                        tool_call=ToolCall(
                            id=str(content_block.get("id", "")),
                            name=str(content_block.get("name", "")),
                            arguments="",
                        ),
                        raw=obj,
                    )
                )
                return True
        return False

    if msg_type == "tool_use":
        tool_input = obj.get("tool_input", {})
        result.events.append(
            JsonEvent(
                event_type="tool_use",
                tool_call=ToolCall(
                    id="",
                    name=str(obj.get("tool_name", "")),
                    arguments=json.dumps(tool_input),
                ),
                raw=obj,
            )
        )
        return True

    if msg_type == "tool_result":
        result.events.append(
            JsonEvent(
                event_type="tool_result",
                tool_result=ToolResult(
                    tool_call_id=str(obj.get("tool_use_id", "")),
                    content=str(obj.get("content", "")),
                    is_error=bool(obj.get("is_error", False)),
                ),
                raw=obj,
            )
        )
        return True

    if msg_type == "result":
        subtype = str(obj.get("subtype", ""))
        if subtype == "success":
            result.final_text = str(obj.get("result", result.final_text))
            result.cost_usd = float(obj.get("cost_usd", 0.0))
            result.duration_ms = int(obj.get("duration_ms", 0))
            usage = obj.get("usage", {})
            if isinstance(usage, dict):
                result.usage = {
                    str(k): int(v) for k, v in usage.items() if isinstance(v, int)
                }
            result.events.append(
                JsonEvent(event_type="result", text=result.final_text, raw=obj)
            )
            return True
        elif subtype == "error":
            result.error = str(obj.get("error", ""))
            result.events.append(
                JsonEvent(event_type="error", text=result.error, raw=obj)
            )
            return True
    return False


KIMI_PASSTHROUGH_EVENTS = {
    "TurnBegin",
    "StepBegin",
    "StepInterrupted",
    "TurnEnd",
    "StatusUpdate",
    "HookTriggered",
    "HookResolved",
    "ApprovalRequest",
    "SubagentEvent",
    "ToolCallRequest",
}


def _apply_kimi_obj(result: ParsedJsonOutput, obj: dict[str, Any]) -> bool:
    result.raw_lines.append(obj)
    wire_type = str(obj.get("type", ""))
    if wire_type in KIMI_PASSTHROUGH_EVENTS:
        result.events.append(JsonEvent(event_type=wire_type.lower(), raw=obj))
        return True

    role = str(obj.get("role", ""))
    if role == "assistant":
        content = obj.get("content", "")
        tool_calls = obj.get("tool_calls")
        if isinstance(content, str):
            result.final_text = content
            result.events.append(
                JsonEvent(event_type="assistant", text=content, raw=obj)
            )
        elif isinstance(content, list):
            texts: list[str] = []
            for part in content:
                if not isinstance(part, dict):
                    continue
                part_type = part.get("type", "")
                if part_type == "text":
                    texts.append(str(part.get("text", "")))
                elif part_type == "think":
                    result.events.append(
                        JsonEvent(
                            event_type="thinking",
                            thinking=str(part.get("think", "")),
                            raw=obj,
                        )
                    )
            if texts:
                text = "\n".join(texts)
                result.final_text = text
                result.events.append(
                    JsonEvent(event_type="assistant", text=text, raw=obj)
                )
        if isinstance(tool_calls, list):
            for tool_call_data in tool_calls:
                if not isinstance(tool_call_data, dict):
                    continue
                fn = tool_call_data.get("function", {})
                if not isinstance(fn, dict):
                    fn = {}
                result.events.append(
                    JsonEvent(
                        event_type="tool_call",
                        tool_call=ToolCall(
                            id=str(tool_call_data.get("id", "")),
                            name=str(fn.get("name", "")),
                            arguments=str(fn.get("arguments", "")),
                        ),
                        raw=obj,
                    )
                )
        return True

    if role == "tool":
        content = obj.get("content", [])
        texts: list[str] = []
        if isinstance(content, list):
            for part in content:
                if (
                    isinstance(part, dict)
                    and part.get("type") == "text"
                    and not str(part.get("text", "")).startswith("<system>")
                ):
                    texts.append(str(part.get("text", "")))
        result.events.append(
            JsonEvent(
                event_type="tool_result",
                tool_result=ToolResult(
                    tool_call_id=str(obj.get("tool_call_id", "")),
                    content="\n".join(texts),
                ),
                raw=obj,
            )
        )
        return True
    return False


def parse_opencode_json(raw_stdout: str) -> ParsedJsonOutput:
    result = _new_output("opencode")
    for line in raw_stdout.splitlines():
        obj, raw_line = _parse_json_line(line)
        if obj is not None and not _apply_opencode_obj(result, obj):
            result.unknown_json_lines.append(raw_line)
    return result


def parse_claude_code_json(raw_stdout: str) -> ParsedJsonOutput:
    result = _new_output("claude-code")
    for line in raw_stdout.splitlines():
        obj, raw_line = _parse_json_line(line)
        if obj is not None and not _apply_claude_obj(result, obj):
            result.unknown_json_lines.append(raw_line)
    return result


def parse_kimi_json(raw_stdout: str) -> ParsedJsonOutput:
    result = _new_output("kimi")
    for line in raw_stdout.splitlines():
        obj, raw_line = _parse_json_line(line)
        if obj is not None and not _apply_kimi_obj(result, obj):
            result.unknown_json_lines.append(raw_line)
    return result


PARSERS = {
    "opencode": parse_opencode_json,
    "claude-code": parse_claude_code_json,
    "kimi": parse_kimi_json,
}


def parse_json_output(raw_stdout: str, schema: str) -> ParsedJsonOutput:
    parser = PARSERS.get(schema)
    if parser is None:
        return ParsedJsonOutput(schema_name=schema, error=f"unknown schema: {schema}")
    return parser(raw_stdout)


def _style(text: str, color_code: str, enabled: bool) -> str:
    if not enabled:
        return text
    return f"\x1b[{color_code}m{text}{RESET}"


def _summarize_text(text: str, *, max_lines: int = 8, max_chars: int = 400) -> str:
    lines = text.strip().splitlines()
    if not lines:
        return ""
    clipped_lines = lines[:max_lines]
    clipped = "\n".join(clipped_lines)
    truncated = len(lines) > max_lines or len(clipped) > max_chars
    if len(clipped) > max_chars:
        clipped = clipped[:max_chars].rstrip()
    if truncated:
        clipped += " …"
    return clipped


def _parse_tool_arguments(arguments: str) -> dict[str, Any]:
    if not arguments:
        return {}
    try:
        parsed = json.loads(arguments)
    except json.JSONDecodeError:
        return {}
    if isinstance(parsed, dict):
        return parsed
    return {}


def _bash_command_preview(tool_call: ToolCall) -> str:
    args = _parse_tool_arguments(tool_call.arguments)
    for key in ("command", "cmd", "bash_command", "script"):
        value = args.get(key)
        if isinstance(value, str) and value.strip():
            preview = value.strip()
            if len(preview) > 400:
                preview = preview[:400].rstrip() + " …"
            return preview
    return ""


def _tool_preview(tool_name: str, text: str) -> str:
    normalized = tool_name.lower()
    if normalized in {
        "read",
        "write",
        "edit",
        "multiedit",
        "read_file",
        "write_file",
        "edit_file",
    }:
        return ""
    return _summarize_text(text)


def resolve_human_tty(
    tty: bool,
    force_color: str | None = None,
    no_color: str | None = None,
) -> bool:
    if force_color:
        return True
    if no_color:
        return False
    return tty


class FormattedRenderer:
    def __init__(self, *, show_thinking: bool = False, tty: bool = False) -> None:
        self.show_thinking = show_thinking
        self.tty = tty
        self._seen_final_texts: set[str] = set()
        self._tool_calls_by_id: dict[str, ToolCall] = {}
        self._pending_tool_call: ToolCall | None = None
        self._streamed_assistant_buffer = ""
        self._plain_text_tool_work = False

    def render_output(self, output: ParsedJsonOutput) -> str:
        parts: list[str] = []
        for event in output.events:
            rendered = self.render_event(event)
            if rendered:
                parts.append(rendered)
        return "\n".join(parts)

    def render_event(self, event: JsonEvent) -> str:
        if event.event_type == "text_delta" and event.text:
            self._streamed_assistant_buffer += event.text
            return self._render_message("assistant", event.text)

        if event.event_type in {"assistant", "text"} and event.text:
            if (
                self._streamed_assistant_buffer
                and event.text == self._streamed_assistant_buffer
            ):
                self._seen_final_texts.add(event.text)
                self._streamed_assistant_buffer = ""
                return ""
            self._streamed_assistant_buffer = ""
            return self._render_message("assistant", event.text)

        if event.event_type == "result" and event.text:
            if (
                self._streamed_assistant_buffer
                and event.text == self._streamed_assistant_buffer
            ):
                self._seen_final_texts.add(event.text)
                self._streamed_assistant_buffer = ""
                return ""
            if event.text in self._seen_final_texts:
                return ""
            self._streamed_assistant_buffer = ""
            return self._render_message("success", event.text)

        if event.event_type in {"thinking", "thinking_delta"} and event.thinking:
            if not self.show_thinking:
                return ""
            return self._render_message("thinking", event.thinking)

        if (
            event.event_type in {"tool_use", "tool_use_start", "tool_call"}
            and event.tool_call
        ):
            tool_call = event.tool_call
            self._streamed_assistant_buffer = ""
            if tool_call.id:
                self._tool_calls_by_id[tool_call.id] = tool_call
            self._pending_tool_call = tool_call
            self._plain_text_tool_work = True
            return self._render_tool_start(tool_call)

        if event.event_type == "tool_input_delta" and event.text:
            if self._pending_tool_call is not None:
                self._pending_tool_call.arguments += event.text
            return ""

        if event.event_type == "tool_result" and event.tool_result:
            self._streamed_assistant_buffer = ""
            return self._render_tool_result(event.tool_result)

        if event.event_type == "error" and event.text:
            self._streamed_assistant_buffer = ""
            return self._render_message("error", event.text)

        return ""

    def _render_message(self, kind: str, text: str) -> str:
        if kind in {"assistant", "success"}:
            self._seen_final_texts.add(text)
        if kind == "assistant":
            prefix = self._prefix("💬", "[assistant]", "96")
        elif kind == "thinking":
            prefix = self._prefix("🧠", "[thinking]", "2;35")
        elif kind == "success":
            prefix = self._prefix("✅", "[ok]", "92")
        else:
            prefix = self._prefix("❌", "[error]", "91")
        return self._with_prefix(prefix, text)

    def _render_tool_start(self, tool_call: ToolCall) -> str:
        prefix = self._prefix("🛠️", "[tool:start]", "94")
        detail = tool_call.name
        bash_preview = _bash_command_preview(tool_call)
        if bash_preview:
            detail += f": {bash_preview}"
        return self._with_prefix(prefix, detail)

    def _render_tool_result(self, tool_result: ToolResult) -> str:
        prefix = self._prefix("📎", "[tool:result]", "36")
        tool_call = self._tool_calls_by_id.get(
            tool_result.tool_call_id, self._pending_tool_call
        )
        tool_name = tool_call.name if tool_call else "tool"
        status = "error" if tool_result.is_error else "ok"
        summary = f"{tool_name} ({status})"
        if tool_call is not None:
            bash_preview = _bash_command_preview(tool_call)
            if bash_preview:
                summary += f": {bash_preview}"
        preview = _tool_preview(tool_name, tool_result.content)
        if preview:
            summary += f"\n{preview}"
        return self._with_prefix(prefix, summary)

    def _prefix(self, emoji: str, plain: str, color_code: str) -> str:
        if self.tty:
            return _style(emoji, color_code, True)
        if self._plain_text_tool_work and plain in {
            "[assistant]",
            "[thinking]",
            "[ok]",
            "[error]",
        }:
            return plain
        return plain

    def _with_prefix(self, prefix: str, text: str) -> str:
        lines = text.splitlines() or [""]
        return "\n".join(f"{prefix} {line}" if line else prefix for line in lines)


class StructuredStreamProcessor:
    def __init__(self, schema: str, renderer: FormattedRenderer) -> None:
        self._renderer = renderer
        self._result = _new_output(schema)
        self._apply = {
            "opencode": _apply_opencode_obj,
            "claude-code": _apply_claude_obj,
            "kimi": _apply_kimi_obj,
        }.get(schema)
        self._buffer = ""
        self._unknown_lines: list[str] = []

    def feed(self, chunk: str) -> str:
        if self._apply is None:
            return ""
        self._buffer += chunk
        parts: list[str] = []
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            obj, raw_line = _parse_json_line(line)
            if obj is None:
                continue
            before = len(self._result.events)
            if not self._apply(self._result, obj):
                self._unknown_lines.append(raw_line)
            for event in self._result.events[before:]:
                rendered = self._renderer.render_event(event)
                if rendered:
                    parts.append(rendered)
        return "\n".join(parts)

    def finish(self) -> str:
        if self._buffer.strip() and self._apply is not None:
            obj, raw_line = _parse_json_line(self._buffer)
            self._buffer = ""
            if obj is not None:
                before = len(self._result.events)
                if not self._apply(self._result, obj):
                    self._unknown_lines.append(raw_line)
                parts: list[str] = []
                for event in self._result.events[before:]:
                    rendered = self._renderer.render_event(event)
                    if rendered:
                        parts.append(rendered)
                return "\n".join(parts)
        return ""

    def take_unknown_json_lines(self) -> list[str]:
        lines = list(self._unknown_lines)
        self._unknown_lines.clear()
        return lines


def render_parsed(
    output: ParsedJsonOutput,
    *,
    show_thinking: bool = True,
    tty: bool = False,
) -> str:
    renderer = FormattedRenderer(show_thinking=show_thinking, tty=tty)
    rendered = renderer.render_output(output)
    return rendered if rendered else output.final_text

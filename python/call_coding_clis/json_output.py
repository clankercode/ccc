from __future__ import annotations

from dataclasses import dataclass, field
import json
from typing import Any


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


def parse_opencode_json(raw_stdout: str) -> ParsedJsonOutput:
    result = ParsedJsonOutput(schema_name="opencode")
    for line in raw_stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        result.raw_lines.append(obj)
        if "response" in obj:
            text = obj["response"]
            result.final_text = text
            result.events.append(JsonEvent(event_type="text", text=text, raw=obj))
        elif "error" in obj:
            result.error = obj["error"]
            result.events.append(
                JsonEvent(event_type="error", text=obj["error"], raw=obj)
            )
    return result


def parse_claude_code_json(raw_stdout: str) -> ParsedJsonOutput:
    result = ParsedJsonOutput(schema_name="claude-code")
    for line in raw_stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        result.raw_lines.append(obj)
        msg_type = obj.get("type", "")

        if msg_type == "system":
            sub = obj.get("subtype", "")
            if sub == "init":
                result.session_id = obj.get("session_id", "")
            elif sub == "api_retry":
                result.events.append(JsonEvent(event_type="system_retry", raw=obj))

        elif msg_type == "assistant":
            message = obj.get("message", {})
            content = message.get("content", [])
            texts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block.get("text", ""))
            if texts:
                text = "\n".join(texts)
                result.final_text = text
                result.events.append(
                    JsonEvent(event_type="assistant", text=text, raw=obj)
                )
            usage = message.get("usage", {})
            if usage:
                result.usage = usage

        elif msg_type == "stream_event":
            event = obj.get("event", {})
            event_type = event.get("type", "")
            if event_type == "content_block_delta":
                delta = event.get("delta", {})
                delta_type = delta.get("type", "")
                if delta_type == "text_delta":
                    result.events.append(
                        JsonEvent(
                            event_type="text_delta",
                            text=delta.get("text", ""),
                            raw=obj,
                        )
                    )
                elif delta_type == "thinking_delta":
                    result.events.append(
                        JsonEvent(
                            event_type="thinking_delta",
                            thinking=delta.get("thinking", ""),
                            raw=obj,
                        )
                    )
                elif delta_type == "input_json_delta":
                    result.events.append(
                        JsonEvent(
                            event_type="tool_input_delta",
                            text=delta.get("partial_json", ""),
                            raw=obj,
                        )
                    )
            elif event_type == "content_block_start":
                cb = event.get("content_block", {})
                cb_type = cb.get("type", "")
                if cb_type == "thinking":
                    result.events.append(
                        JsonEvent(event_type="thinking_start", raw=obj)
                    )
                elif cb_type == "tool_use":
                    result.events.append(
                        JsonEvent(
                            event_type="tool_use_start",
                            tool_call=ToolCall(
                                id=cb.get("id", ""),
                                name=cb.get("name", ""),
                                arguments="",
                            ),
                            raw=obj,
                        )
                    )

        elif msg_type == "tool_use":
            tc = ToolCall(
                id="",
                name=obj.get("tool_name", ""),
                arguments=json.dumps(obj.get("tool_input", {})),
            )
            result.events.append(
                JsonEvent(event_type="tool_use", tool_call=tc, raw=obj)
            )

        elif msg_type == "tool_result":
            tr = ToolResult(
                tool_call_id=obj.get("tool_use_id", ""),
                content=obj.get("content", ""),
                is_error=obj.get("is_error", False),
            )
            result.events.append(
                JsonEvent(event_type="tool_result", tool_result=tr, raw=obj)
            )

        elif msg_type == "result":
            sub = obj.get("subtype", "")
            if sub == "success":
                result.final_text = obj.get("result", result.final_text)
                result.cost_usd = obj.get("cost_usd", 0.0)
                result.duration_ms = obj.get("duration_ms", 0)
                result.usage = obj.get("usage", result.usage)
                result.events.append(
                    JsonEvent(event_type="result", text=result.final_text, raw=obj)
                )
            elif sub == "error":
                result.error = obj.get("error", "")
                result.events.append(
                    JsonEvent(event_type="error", text=result.error, raw=obj)
                )

    return result


def parse_kimi_json(raw_stdout: str) -> ParsedJsonOutput:
    result = ParsedJsonOutput(schema_name="kimi")
    for line in raw_stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        result.raw_lines.append(obj)

        wire_type = obj.get("type", "")
        if wire_type in (
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
        ):
            result.events.append(JsonEvent(event_type=wire_type.lower(), raw=obj))
            continue

        role = obj.get("role", "")
        if role == "assistant":
            content = obj.get("content", "")
            tool_calls = obj.get("tool_calls")
            if isinstance(content, str):
                result.final_text = content
                result.events.append(
                    JsonEvent(event_type="assistant", text=content, raw=obj)
                )
            elif isinstance(content, list):
                texts = []
                for part in content:
                    if isinstance(part, dict):
                        part_type = part.get("type", "")
                        if part_type == "text":
                            texts.append(part.get("text", ""))
                        elif part_type == "think":
                            result.events.append(
                                JsonEvent(
                                    event_type="thinking",
                                    thinking=part.get("think", ""),
                                    raw=obj,
                                )
                            )
                if texts:
                    text = "\n".join(texts)
                    result.final_text = text
                    result.events.append(
                        JsonEvent(event_type="assistant", text=text, raw=obj)
                    )
            if tool_calls:
                for tc_data in tool_calls:
                    fn = tc_data.get("function", {})
                    tc = ToolCall(
                        id=tc_data.get("id", ""),
                        name=fn.get("name", ""),
                        arguments=fn.get("arguments", ""),
                    )
                    result.events.append(
                        JsonEvent(event_type="tool_call", tool_call=tc, raw=obj)
                    )

        elif role == "tool":
            content = obj.get("content", [])
            texts = []
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    text = part.get("text", "")
                    if not text.startswith("<system>"):
                        texts.append(text)
            tr = ToolResult(
                tool_call_id=obj.get("tool_call_id", ""),
                content="\n".join(texts),
            )
            result.events.append(
                JsonEvent(event_type="tool_result", tool_result=tr, raw=obj)
            )

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


def render_parsed(output: ParsedJsonOutput) -> str:
    parts: list[str] = []
    for event in output.events:
        if event.event_type in ("text", "assistant", "result"):
            if event.text:
                parts.append(event.text)
        elif event.event_type == "thinking_delta" or event.event_type == "thinking":
            if event.thinking:
                parts.append(f"[thinking] {event.thinking}")
        elif event.event_type == "tool_use":
            if event.tool_call:
                parts.append(f"[tool] {event.tool_call.name}")
        elif event.event_type == "tool_result":
            if event.tool_result:
                parts.append(f"[tool_result] {event.tool_result.content}")
        elif event.event_type == "error":
            if event.text:
                parts.append(f"[error] {event.text}")
    return "\n".join(parts) if parts else output.final_text

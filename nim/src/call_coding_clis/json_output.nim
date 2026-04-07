import std/[json, strutils, options]

type
  ToolCall* = object
    id*: string
    name*: string
    arguments*: string

  ToolResult* = object
    toolCallId*: string
    content*: string
    isError*: bool

  JsonEvent* = object
    eventType*: string
    text*: string
    thinking*: string
    toolCall*: Option[ToolCall]
    toolResult*: Option[ToolResult]
    raw*: JsonNode

  ParsedJsonOutput* = object
    schemaName*: string
    events*: seq[JsonEvent]
    finalText*: string
    sessionId*: string
    error*: string
    usage*: JsonNode
    costUsd*: float
    durationMs*: int
    rawLines*: seq[JsonNode]

proc newToolCall*(id = "", name = "", arguments = ""): ToolCall =
  ToolCall(id: id, name: name, arguments: arguments)

proc newToolResult*(toolCallId = "", content = "", isError = false): ToolResult =
  ToolResult(toolCallId: toolCallId, content: content, isError: isError)

proc newJsonEvent*(eventType = "", text = "", thinking = "",
                   toolCall: Option[ToolCall] = none(ToolCall),
                   toolResult: Option[ToolResult] = none(ToolResult),
                   raw = newJNull()): JsonEvent =
  JsonEvent(eventType: eventType, text: text, thinking: thinking,
            toolCall: toolCall, toolResult: toolResult, raw: raw)

proc newParsedJsonOutput*(schemaName = ""): ParsedJsonOutput =
  ParsedJsonOutput(schemaName: schemaName, usage: newJObject(), rawLines: @[])

proc safeGetStr(node: JsonNode, key: string): string =
  if node.kind == JObject and node.hasKey(key):
    let v = node[key]
    if v.kind == JString: return v.getStr()
  ""

proc safeGetInt(node: JsonNode, key: string): int =
  if node.kind == JObject and node.hasKey(key):
    let v = node[key]
    if v.kind == JInt: return v.getInt()
  0

proc safeGetFloat(node: JsonNode, key: string): float =
  if node.kind == JObject and node.hasKey(key):
    let v = node[key]
    if v.kind == JFloat: return v.getFloat()
    if v.kind == JInt: return v.getInt().float
  0.0

proc safeGetBool(node: JsonNode, key: string): bool =
  if node.kind == JObject and node.hasKey(key):
    let v = node[key]
    if v.kind == JBool: return v.getBool()
  false

proc parseOpencodeJson*(rawStdout: string): ParsedJsonOutput =
  result = newParsedJsonOutput("opencode")
  for line in rawStdout.strip().splitLines():
    let line = line.strip()
    if line.len == 0: continue
    var obj: JsonNode
    try:
      obj = parseJson(line)
    except JsonParsingError:
      continue
    result.rawLines.add(obj)
    if obj.kind == JObject:
      if obj.hasKey("response"):
        let text = obj["response"].getStr()
        result.finalText = text
        result.events.add(newJsonEvent("text", text = text, raw = obj))
      elif obj.hasKey("error"):
        let errMsg = obj["error"].getStr()
        result.error = errMsg
        result.events.add(newJsonEvent("error", text = errMsg, raw = obj))

proc parseClaudeCodeJson*(rawStdout: string): ParsedJsonOutput =
  result = newParsedJsonOutput("claude-code")
  for line in rawStdout.strip().splitLines():
    let line = line.strip()
    if line.len == 0: continue
    var obj: JsonNode
    try:
      obj = parseJson(line)
    except JsonParsingError:
      continue
    result.rawLines.add(obj)
    if obj.kind != JObject: continue
    let msgType = safeGetStr(obj, "type")

    if msgType == "system":
      let sub = safeGetStr(obj, "subtype")
      if sub == "init":
        result.sessionId = safeGetStr(obj, "session_id")
      elif sub == "api_retry":
        result.events.add(newJsonEvent("system_retry", raw = obj))

    elif msgType == "assistant":
      if obj.hasKey("message"):
        let message = obj["message"]
        var texts: seq[string] = @[]
        if message.hasKey("content") and message["content"].kind == JArray:
          for blk in message["content"]:
            if blk.kind == JObject and safeGetStr(blk, "type") == "text":
              texts.add(safeGetStr(blk, "text"))
        if texts.len > 0:
          let text = texts.join("\n")
          result.finalText = text
          result.events.add(newJsonEvent("assistant", text = text, raw = obj))
        if message.hasKey("usage"):
          result.usage = message["usage"]

    elif msgType == "stream_event":
      if obj.hasKey("event"):
        let event = obj["event"]
        let eventType = safeGetStr(event, "type")

        if eventType == "content_block_delta":
          if event.hasKey("delta"):
            let delta = event["delta"]
            let deltaType = safeGetStr(delta, "type")
            if deltaType == "text_delta":
              result.events.add(newJsonEvent("text_delta", text = safeGetStr(delta, "text"), raw = obj))
            elif deltaType == "thinking_delta":
              result.events.add(newJsonEvent("thinking_delta", thinking = safeGetStr(delta, "thinking"), raw = obj))
            elif deltaType == "input_json_delta":
              result.events.add(newJsonEvent("tool_input_delta", text = safeGetStr(delta, "partial_json"), raw = obj))

        elif eventType == "content_block_start":
          if event.hasKey("content_block"):
            let cb = event["content_block"]
            let cbType = safeGetStr(cb, "type")
            if cbType == "thinking":
              result.events.add(newJsonEvent("thinking_start", raw = obj))
            elif cbType == "tool_use":
              let tc = newToolCall(id = safeGetStr(cb, "id"), name = safeGetStr(cb, "name"))
              result.events.add(newJsonEvent("tool_use_start", toolCall = some(tc), raw = obj))

    elif msgType == "tool_use":
      let toolInput = if obj.hasKey("tool_input"): obj["tool_input"] else: newJObject()
      let tc = newToolCall(name = safeGetStr(obj, "tool_name"), arguments = $toolInput)
      result.events.add(newJsonEvent("tool_use", toolCall = some(tc), raw = obj))

    elif msgType == "tool_result":
      let tr = newToolResult(
        toolCallId = safeGetStr(obj, "tool_use_id"),
        content = safeGetStr(obj, "content"),
        isError = safeGetBool(obj, "is_error")
      )
      result.events.add(newJsonEvent("tool_result", toolResult = some(tr), raw = obj))

    elif msgType == "result":
      let sub = safeGetStr(obj, "subtype")
      if sub == "success":
        let r = safeGetStr(obj, "result")
        result.finalText = if r.len > 0: r else: result.finalText
        result.costUsd = safeGetFloat(obj, "cost_usd")
        result.durationMs = safeGetInt(obj, "duration_ms")
        if obj.hasKey("usage"):
          result.usage = obj["usage"]
        result.events.add(newJsonEvent("result", text = result.finalText, raw = obj))
      elif sub == "error":
        result.error = safeGetStr(obj, "error")
        result.events.add(newJsonEvent("error", text = result.error, raw = obj))

proc parseKimiJson*(rawStdout: string): ParsedJsonOutput =
  result = newParsedJsonOutput("kimi")
  let passthroughTypes = [
    "TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd",
    "StatusUpdate", "HookTriggered", "HookResolved",
    "ApprovalRequest", "SubagentEvent", "ToolCallRequest"
  ]
  for line in rawStdout.strip().splitLines():
    let line = line.strip()
    if line.len == 0: continue
    var obj: JsonNode
    try:
      obj = parseJson(line)
    except JsonParsingError:
      continue
    result.rawLines.add(obj)
    if obj.kind != JObject: continue

    let wireType = safeGetStr(obj, "type")
    if wireType in passthroughTypes:
      result.events.add(newJsonEvent(wireType.toLowerAscii(), raw = obj))
      continue

    let role = safeGetStr(obj, "role")
    if role == "assistant":
      if obj.hasKey("content"):
        let content = obj["content"]
        if content.kind == JString:
          result.finalText = content.getStr()
          result.events.add(newJsonEvent("assistant", text = content.getStr(), raw = obj))
        elif content.kind == JArray:
          var texts: seq[string] = @[]
          for part in content:
            if part.kind != JObject: continue
            let partType = safeGetStr(part, "type")
            if partType == "text":
              texts.add(safeGetStr(part, "text"))
            elif partType == "think":
              result.events.add(newJsonEvent("thinking", thinking = safeGetStr(part, "think"), raw = obj))
          if texts.len > 0:
            let text = texts.join("\n")
            result.finalText = text
            result.events.add(newJsonEvent("assistant", text = text, raw = obj))

      if obj.hasKey("tool_calls") and obj["tool_calls"].kind == JArray:
        for tcData in obj["tool_calls"]:
          let fn = if tcData.hasKey("function"): tcData["function"] else: newJObject()
          let tc = newToolCall(
            id = safeGetStr(tcData, "id"),
            name = safeGetStr(fn, "name"),
            arguments = safeGetStr(fn, "arguments")
          )
          result.events.add(newJsonEvent("tool_call", toolCall = some(tc), raw = obj))

    elif role == "tool":
      var texts: seq[string] = @[]
      if obj.hasKey("content") and obj["content"].kind == JArray:
        for part in obj["content"]:
          if part.kind == JObject and safeGetStr(part, "type") == "text":
            let t = safeGetStr(part, "text")
            if not t.startsWith("<system>"):
              texts.add(t)
      let tr = newToolResult(
        toolCallId = safeGetStr(obj, "tool_call_id"),
        content = texts.join("\n")
      )
      result.events.add(newJsonEvent("tool_result", toolResult = some(tr), raw = obj))

proc parseJsonOutput*(rawStdout: string, schema: string): ParsedJsonOutput =
  case schema
  of "opencode": parseOpencodeJson(rawStdout)
  of "claude-code": parseClaudeCodeJson(rawStdout)
  of "kimi": parseKimiJson(rawStdout)
  else: ParsedJsonOutput(schemaName: schema, error: "unknown schema: " & schema)

proc renderParsed*(output: ParsedJsonOutput): string =
  var parts: seq[string] = @[]
  for event in output.events:
    case event.eventType
    of "text", "assistant", "result":
      if event.text.len > 0:
        parts.add(event.text)
    of "thinking_delta", "thinking":
      if event.thinking.len > 0:
        parts.add("[thinking] " & event.thinking)
    of "tool_use":
      if event.toolCall.isSome:
        parts.add("[tool] " & event.toolCall.get().name)
    of "tool_result":
      if event.toolResult.isSome:
        parts.add("[tool_result] " & event.toolResult.get().content)
    of "error":
      if event.text.len > 0:
        parts.add("[error] " & event.text)
  if parts.len > 0:
    parts.join("\n")
  else:
    output.finalText

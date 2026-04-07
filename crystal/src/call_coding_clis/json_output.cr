require "json"

struct ToolCall
  getter id : String
  getter name : String
  getter arguments : String

  def initialize(@id : String = "", @name : String = "", @arguments : String = "")
  end
end

struct ToolResult
  getter tool_call_id : String
  getter content : String
  getter is_error : Bool

  def initialize(@tool_call_id : String = "", @content : String = "", @is_error : Bool = false)
  end
end

struct JsonEvent
  getter event_type : String
  getter text : String
  getter thinking : String
  getter tool_call : ToolCall?
  getter tool_result : ToolResult?
  getter raw : Hash(String, JSON::Any)

  def initialize(
    @event_type : String = "",
    @text : String = "",
    @thinking : String = "",
    @tool_call : ToolCall? = nil,
    @tool_result : ToolResult? = nil,
    @raw : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
  )
  end
end

struct ParsedJsonOutput
  getter schema_name : String
  getter events : Array(JsonEvent)
  getter final_text : String
  getter session_id : String
  getter error : String
  getter usage : Hash(String, JSON::Any)
  getter cost_usd : Float64
  getter duration_ms : Int32
  getter raw_lines : Array(Hash(String, JSON::Any))

  def initialize(
    @schema_name : String = "",
    @events : Array(JsonEvent) = [] of JsonEvent,
    @final_text : String = "",
    @session_id : String = "",
    @error : String = "",
    @usage : Hash(String, JSON::Any) = Hash(String, JSON::Any).new,
    @cost_usd : Float64 = 0.0,
    @duration_ms : Int32 = 0,
    @raw_lines : Array(Hash(String, JSON::Any)) = [] of Hash(String, JSON::Any)
  )
  end
end

private def obj_to_hash(obj : JSON::Any) : Hash(String, JSON::Any)
  h = Hash(String, JSON::Any).new
  obj.as_h.each { |k, v| h[k] = v }
  h
end

private def any_to_s(v : JSON::Any?) : String
  return "" if v.nil?
  s = v.as_s?
  return s if s
  v.to_json
end

private def any_to_f(v : JSON::Any?) : Float64
  return 0.0 if v.nil?
  f = v.as_f?
  return f if f
  i = v.as_i?
  return i.to_f64 if i
  0.0
end

private def any_to_i(v : JSON::Any?) : Int32
  return 0 if v.nil?
  i = v.as_i?
  return i if i
  0
end

private def any_to_b(v : JSON::Any?) : Bool
  return false if v.nil?
  v.as_bool? || false
end

def parse_opencode_json(raw_stdout : String) : ParsedJsonOutput
  events = [] of JsonEvent
  raw_lines = [] of Hash(String, JSON::Any)
  final_text = ""
  error = ""

  raw_stdout.strip.split('\n').each do |line|
    line = line.strip
    next if line.empty?
    begin
      obj = JSON.parse(line)
    rescue JSON::ParseException
      next
    end
    h = obj_to_hash(obj)
    raw_lines << h

    if obj.as_h.has_key?("response")
      text = any_to_s(obj["response"])
      final_text = text
      events << JsonEvent.new(event_type: "text", text: text, raw: h)
    elsif obj.as_h.has_key?("error")
      error = any_to_s(obj["error"])
      events << JsonEvent.new(event_type: "error", text: error, raw: h)
    end
  end

  ParsedJsonOutput.new(schema_name: "opencode", events: events, final_text: final_text, error: error, raw_lines: raw_lines)
end

def parse_claude_code_json(raw_stdout : String) : ParsedJsonOutput
  events = [] of JsonEvent
  raw_lines = [] of Hash(String, JSON::Any)
  final_text = ""
  session_id = ""
  error = ""
  usage = Hash(String, JSON::Any).new
  cost_usd = 0.0
  duration_ms = 0

  raw_stdout.strip.split('\n').each do |line|
    line = line.strip
    next if line.empty?
    begin
      obj = JSON.parse(line)
    rescue JSON::ParseException
      next
    end
    h = obj_to_hash(obj)
    raw_lines << h
    msg_type = any_to_s(obj["type"]?)

    if msg_type == "system"
      sub = any_to_s(obj["subtype"]?)
      if sub == "init"
        session_id = any_to_s(obj["session_id"]?)
      elsif sub == "api_retry"
        events << JsonEvent.new(event_type: "system_retry", raw: h)
      end

    elsif msg_type == "assistant"
      message = obj["message"]?
      if message
        content = message["content"]?
        texts = [] of String
        if content
          content.as_a.each do |block|
            bh = block.as_h?
            next unless bh
            if any_to_s(block["type"]?) == "text"
              texts << any_to_s(block["text"]?)
            end
          end
        end
        if texts.any?
          text = texts.join("\n")
          final_text = text
          events << JsonEvent.new(event_type: "assistant", text: text, raw: h)
        end
        msg_usage = message["usage"]?
        if msg_usage
          usage = obj_to_hash(msg_usage)
        end
      end

    elsif msg_type == "stream_event"
      event = obj["event"]?
      next unless event
      event_type_str = any_to_s(event["type"]?)

      if event_type_str == "content_block_delta"
        delta = event["delta"]?
        next unless delta
        delta_type = any_to_s(delta["type"]?)

        if delta_type == "text_delta"
          events << JsonEvent.new(event_type: "text_delta", text: any_to_s(delta["text"]?), raw: h)
        elsif delta_type == "thinking_delta"
          events << JsonEvent.new(event_type: "thinking_delta", thinking: any_to_s(delta["thinking"]?), raw: h)
        elsif delta_type == "input_json_delta"
          events << JsonEvent.new(event_type: "tool_input_delta", text: any_to_s(delta["partial_json"]?), raw: h)
        end

      elsif event_type_str == "content_block_start"
        cb = event["content_block"]?
        next unless cb
        cb_type = any_to_s(cb["type"]?)

        if cb_type == "thinking"
          events << JsonEvent.new(event_type: "thinking_start", raw: h)
        elsif cb_type == "tool_use"
          tc = ToolCall.new(id: any_to_s(cb["id"]?), name: any_to_s(cb["name"]?))
          events << JsonEvent.new(event_type: "tool_use_start", tool_call: tc, raw: h)
        end
      end

    elsif msg_type == "tool_use"
      tc = ToolCall.new(name: any_to_s(obj["tool_name"]?), arguments: (obj["tool_input"]?).try(&.to_json) || "{}")
      events << JsonEvent.new(event_type: "tool_use", tool_call: tc, raw: h)

    elsif msg_type == "tool_result"
      tr = ToolResult.new(
        tool_call_id: any_to_s(obj["tool_use_id"]?),
        content: any_to_s(obj["content"]?),
        is_error: any_to_b(obj["is_error"]?)
      )
      events << JsonEvent.new(event_type: "tool_result", tool_result: tr, raw: h)

    elsif msg_type == "result"
      sub = any_to_s(obj["subtype"]?)
      if sub == "success"
        result_text = any_to_s(obj["result"]?)
        final_text = result_text.empty? ? final_text : result_text
        cost_usd = any_to_f(obj["cost_usd"]?)
        duration_ms = any_to_i(obj["duration_ms"]?)
        result_usage = obj["usage"]?
        usage = obj_to_hash(result_usage) if result_usage
        events << JsonEvent.new(event_type: "result", text: final_text, raw: h)
      elsif sub == "error"
        error = any_to_s(obj["error"]?)
        events << JsonEvent.new(event_type: "error", text: error, raw: h)
      end
    end
  end

  ParsedJsonOutput.new(
    schema_name: "claude-code",
    events: events,
    final_text: final_text,
    session_id: session_id,
    error: error,
    usage: usage,
    cost_usd: cost_usd,
    duration_ms: duration_ms,
    raw_lines: raw_lines
  )
end

def parse_kimi_json(raw_stdout : String) : ParsedJsonOutput
  events = [] of JsonEvent
  raw_lines = [] of Hash(String, JSON::Any)
  final_text = ""
  error = ""

  passthrough_types = {
    "TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd",
    "StatusUpdate", "HookTriggered", "HookResolved",
    "ApprovalRequest", "SubagentEvent", "ToolCallRequest",
  }

  raw_stdout.strip.split('\n').each do |line|
    line = line.strip
    next if line.empty?
    begin
      obj = JSON.parse(line)
    rescue JSON::ParseException
      next
    end
    h = obj_to_hash(obj)
    raw_lines << h

    wire_type = any_to_s(obj["type"]?)
    if passthrough_types.includes?(wire_type)
      events << JsonEvent.new(event_type: wire_type.downcase, raw: h)
      next
    end

    role = any_to_s(obj["role"]?)
    if role == "assistant"
      content = obj["content"]?
      tool_calls = obj["tool_calls"]?

      if content
        if content_raw = content.as_s?
          final_text = content_raw
          events << JsonEvent.new(event_type: "assistant", text: content_raw, raw: h)
        elsif content_raw = content.as_a?
          texts = [] of String
          content_raw.each do |part|
            part_h = part.as_h?
            next unless part_h
            part_type = any_to_s(part["type"]?)
            if part_type == "text"
              texts << any_to_s(part["text"]?)
            elsif part_type == "think"
              events << JsonEvent.new(event_type: "thinking", thinking: any_to_s(part["think"]?), raw: h)
            end
          end
          if texts.any?
            text = texts.join("\n")
            final_text = text
            events << JsonEvent.new(event_type: "assistant", text: text, raw: h)
          end
        end
      end

      if tool_calls
        tool_calls.as_a.each do |tc_data|
          fn = tc_data["function"]?
          tc = ToolCall.new(
            id: any_to_s(tc_data["id"]?),
            name: fn ? any_to_s(fn["name"]?) : "",
            arguments: fn ? any_to_s(fn["arguments"]?) : ""
          )
          events << JsonEvent.new(event_type: "tool_call", tool_call: tc, raw: h)
        end
      end

    elsif role == "tool"
      content = obj["content"]?
      texts = [] of String
      if content
        content.as_a.each do |part|
          part_h = part.as_h?
          next unless part_h
          if any_to_s(part["type"]?) == "text"
            text = any_to_s(part["text"]?)
            texts << text unless text.starts_with?("<system>")
          end
        end
      end
      tr = ToolResult.new(
        tool_call_id: any_to_s(obj["tool_call_id"]?),
        content: texts.join("\n")
      )
      events << JsonEvent.new(event_type: "tool_result", tool_result: tr, raw: h)
    end
  end

  ParsedJsonOutput.new(
    schema_name: "kimi",
    events: events,
    final_text: final_text,
    error: error,
    raw_lines: raw_lines
  )
end

PARSERS = {
  "opencode"    => ->parse_opencode_json(String),
  "claude-code" => ->parse_claude_code_json(String),
  "kimi"        => ->parse_kimi_json(String),
}

def parse_json_output(raw_stdout : String, schema : String) : ParsedJsonOutput
  parser = PARSERS[schema]?
  return ParsedJsonOutput.new(schema_name: schema, error: "unknown schema: #{schema}") unless parser
  parser.call(raw_stdout)
end

def render_parsed(output : ParsedJsonOutput) : String
  parts = [] of String
  output.events.each do |event|
    case event.event_type
    when "text", "assistant", "result"
      parts << event.text unless event.text.empty?
    when "thinking_delta", "thinking"
      parts << "[thinking] #{event.thinking}" unless event.thinking.empty?
    when "tool_use"
      parts << "[tool] #{event.tool_call.not_nil!.name}" if event.tool_call
    when "tool_result"
      parts << "[tool_result] #{event.tool_result.not_nil!.content}" if event.tool_result
    when "error"
      parts << "[error] #{event.text}" unless event.text.empty?
    end
  end
  parts.empty? ? output.final_text : parts.join("\n")
end

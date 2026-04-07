# frozen_string_literal: true

require "json"

module CallCodingClis
  module JsonOutput
    ToolCall = Struct.new(:id, :name, :arguments, keyword_init: true)
    ToolResult = Struct.new(:tool_call_id, :content, :is_error, keyword_init: true) do
      def initialize(tool_call_id: "", content: "", is_error: false)
        super
      end
    end
    JsonEvent = Struct.new(:event_type, :text, :thinking, :tool_call, :tool_result, :raw, keyword_init: true) do
      def initialize(event_type:, text: "", thinking: "", tool_call: nil, tool_result: nil, raw: {})
        super
      end
    end
    ParsedJsonOutput = Struct.new(:schema_name, :events, :final_text, :session_id, :error, :usage, :cost_usd, :duration_ms, :raw_lines, keyword_init: true) do
      def initialize(schema_name:, events: [], final_text: "", session_id: "", error: "", usage: {}, cost_usd: 0.0, duration_ms: 0, raw_lines: [])
        super
      end
    end

    KIMI_PASSTHROUGH_TYPES = %w[
      TurnBegin StepBegin StepInterrupted TurnEnd StatusUpdate
      HookTriggered HookResolved ApprovalRequest SubagentEvent ToolCallRequest
    ].freeze

    def self.parse_opencode_json(raw_stdout)
      result = ParsedJsonOutput.new(schema_name: "opencode")
      raw_stdout.strip.each_line do |line|
        line = line.strip
        next if line.empty?

        begin
          obj = JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        result.raw_lines << obj
        if obj.key?("response")
          text = obj["response"]
          result.final_text = text
          result.events << JsonEvent.new(event_type: "text", text: text, raw: obj)
        elsif obj.key?("error")
          result.error = obj["error"]
          result.events << JsonEvent.new(event_type: "error", text: obj["error"], raw: obj)
        end
      end
      result
    end

    def self.parse_claude_code_json(raw_stdout)
      result = ParsedJsonOutput.new(schema_name: "claude-code")
      raw_stdout.strip.each_line do |line|
        line = line.strip
        next if line.empty?

        begin
          obj = JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        result.raw_lines << obj
        msg_type = obj["type"] || ""

        case msg_type
        when "system"
          sub = obj["subtype"] || ""
          if sub == "init"
            result.session_id = obj["session_id"] || ""
          elsif sub == "api_retry"
            result.events << JsonEvent.new(event_type: "system_retry", raw: obj)
          end

        when "assistant"
          message = obj["message"] || {}
          content = message["content"] || []
          texts = []
          content.each do |block|
            if block.is_a?(Hash) && block["type"] == "text"
              texts << (block["text"] || "")
            end
          end
          if texts.any?
            text = texts.join("\n")
            result.final_text = text
            result.events << JsonEvent.new(event_type: "assistant", text: text, raw: obj)
          end
          usage = message["usage"]
          result.usage = usage if usage

        when "stream_event"
          event = obj["event"] || {}
          event_type = event["type"] || ""
          if event_type == "content_block_delta"
            delta = event["delta"] || {}
            delta_type = delta["type"] || ""
            case delta_type
            when "text_delta"
              result.events << JsonEvent.new(event_type: "text_delta", text: delta["text"].to_s, raw: obj)
            when "thinking_delta"
              result.events << JsonEvent.new(event_type: "thinking_delta", thinking: delta["thinking"].to_s, raw: obj)
            when "input_json_delta"
              result.events << JsonEvent.new(event_type: "tool_input_delta", text: delta["partial_json"].to_s, raw: obj)
            end
          elsif event_type == "content_block_start"
            cb = event["content_block"] || {}
            cb_type = cb["type"] || ""
            if cb_type == "thinking"
              result.events << JsonEvent.new(event_type: "thinking_start", raw: obj)
            elsif cb_type == "tool_use"
              tc = ToolCall.new(id: cb["id"].to_s, name: cb["name"].to_s, arguments: "")
              result.events << JsonEvent.new(event_type: "tool_use_start", tool_call: tc, raw: obj)
            end
          end

        when "tool_use"
          tc = ToolCall.new(id: "", name: obj["tool_name"].to_s, arguments: JSON.generate(obj["tool_input"] || {}))
          result.events << JsonEvent.new(event_type: "tool_use", tool_call: tc, raw: obj)

        when "tool_result"
          tr = ToolResult.new(
            tool_call_id: obj["tool_use_id"].to_s,
            content: obj["content"].to_s,
            is_error: obj["is_error"] == true
          )
          result.events << JsonEvent.new(event_type: "tool_result", tool_result: tr, raw: obj)

        when "result"
          sub = obj["subtype"] || ""
          if sub == "success"
            result.final_text = obj.fetch("result", result.final_text)
            result.cost_usd = obj.fetch("cost_usd", 0.0)
            result.duration_ms = obj.fetch("duration_ms", 0)
            result.usage = obj.fetch("usage", result.usage)
            result.events << JsonEvent.new(event_type: "result", text: result.final_text, raw: obj)
          elsif sub == "error"
            result.error = obj["error"].to_s
            result.events << JsonEvent.new(event_type: "error", text: result.error, raw: obj)
          end
        end
      end
      result
    end

    def self.parse_kimi_json(raw_stdout)
      result = ParsedJsonOutput.new(schema_name: "kimi")
      raw_stdout.strip.each_line do |line|
        line = line.strip
        next if line.empty?

        begin
          obj = JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        result.raw_lines << obj

        wire_type = obj["type"] || ""
        if KIMI_PASSTHROUGH_TYPES.include?(wire_type)
          result.events << JsonEvent.new(event_type: wire_type.downcase, raw: obj)
          next
        end

        role = obj["role"] || ""
        case role
        when "assistant"
          content = obj["content"]
          tool_calls = obj["tool_calls"]
          if content.is_a?(String)
            result.final_text = content
            result.events << JsonEvent.new(event_type: "assistant", text: content, raw: obj)
          elsif content.is_a?(Array)
            texts = []
            content.each do |part|
              next unless part.is_a?(Hash)
              part_type = part["type"] || ""
              if part_type == "text"
                texts << (part["text"] || "")
              elsif part_type == "think"
                result.events << JsonEvent.new(event_type: "thinking", thinking: part["think"].to_s, raw: obj)
              end
            end
            if texts.any?
              text = texts.join("\n")
              result.final_text = text
              result.events << JsonEvent.new(event_type: "assistant", text: text, raw: obj)
            end
          end
          if tool_calls
            tool_calls.each do |tc_data|
              fn = tc_data["function"] || {}
              tc = ToolCall.new(id: tc_data["id"].to_s, name: fn["name"].to_s, arguments: fn["arguments"].to_s)
              result.events << JsonEvent.new(event_type: "tool_call", tool_call: tc, raw: obj)
            end
          end

        when "tool"
          content = obj["content"] || []
          texts = []
          content.each do |part|
            if part.is_a?(Hash) && part["type"] == "text"
              text = part["text"] || ""
              texts << text unless text.start_with?("<system>")
            end
          end
          tr = ToolResult.new(tool_call_id: obj["tool_call_id"].to_s, content: texts.join("\n"))
          result.events << JsonEvent.new(event_type: "tool_result", tool_result: tr, raw: obj)
        end
      end
      result
    end

    PARSERS = {
      "opencode" => method(:parse_opencode_json),
      "claude-code" => method(:parse_claude_code_json),
      "kimi" => method(:parse_kimi_json),
    }.freeze

    def self.parse_json_output(raw_stdout, schema)
      parser = PARSERS[schema]
      if parser.nil?
        return ParsedJsonOutput.new(schema_name: schema, error: "unknown schema: #{schema}")
      end
      parser.call(raw_stdout)
    end

    def self.render_parsed(output)
      parts = []
      output.events.each do |event|
        case event.event_type
        when "text", "assistant", "result"
          parts << event.text if event.text && !event.text.empty?
        when "thinking_delta", "thinking"
          parts << "[thinking] #{event.thinking}" if event.thinking && !event.thinking.empty?
        when "tool_use"
          parts << "[tool] #{event.tool_call.name}" if event.tool_call
        when "tool_result"
          parts << "[tool_result] #{event.tool_result.content}" if event.tool_result
        when "error"
          parts << "[error] #{event.text}" if event.text && !event.text.empty?
        end
      end
      parts.any? ? parts.join("\n") : output.final_text
    end
  end
end

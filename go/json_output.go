package ccc

import (
	"encoding/json"
	"fmt"
	"strings"
)

type ToolCall struct {
	ID        string
	Name      string
	Arguments string
}

type ToolResult struct {
	ToolCallID string
	Content    string
	IsError    bool
}

type JsonEvent struct {
	EventType  string
	Text       string
	Thinking   string
	ToolCall   *ToolCall
	ToolResult *ToolResult
	Raw        map[string]interface{}
}

type ParsedJsonOutput struct {
	SchemaName string
	Events     []JsonEvent
	FinalText  string
	SessionID  string
	Error      string
	Usage      map[string]int
	CostUSD    float64
	DurationMs int
	RawLines   []map[string]interface{}
}

func parseLine(raw string) []map[string]interface{} {
	var lines []map[string]interface{}
	for _, line := range strings.Split(strings.TrimSpace(raw), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var obj map[string]interface{}
		if err := json.Unmarshal([]byte(line), &obj); err != nil {
			continue
		}
		lines = append(lines, obj)
	}
	return lines
}

func getStr(m map[string]interface{}, key string) string {
	v, _ := m[key].(string)
	return v
}

func getFloat(m map[string]interface{}, key string) float64 {
	v, ok := m[key]
	if !ok {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	}
	return 0
}

func getInt(m map[string]interface{}, key string) int {
	v, ok := m[key]
	if !ok {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	}
	return 0
}

func getBool(m map[string]interface{}, key string) bool {
	v, _ := m[key].(bool)
	return v
}

func getMap(m map[string]interface{}, key string) map[string]interface{} {
	v, _ := m[key].(map[string]interface{})
	return v
}

func getSlice(m map[string]interface{}, key string) []interface{} {
	v, _ := m[key].([]interface{})
	return v
}

func usageFromMap(m map[string]interface{}) map[string]int {
	out := make(map[string]int, len(m))
	for k, v := range m {
		switch n := v.(type) {
		case float64:
			out[k] = int(n)
		case int:
			out[k] = n
		}
	}
	return out
}

func ParseOpenCodeJson(raw string) ParsedJsonOutput {
	result := ParsedJsonOutput{SchemaName: "opencode"}
	for _, obj := range parseLine(raw) {
		result.RawLines = append(result.RawLines, obj)
		if _, ok := obj["response"]; ok {
			text := getStr(obj, "response")
			result.FinalText = text
			result.Events = append(result.Events, JsonEvent{EventType: "text", Text: text, Raw: obj})
		} else if _, ok := obj["error"]; ok {
			errMsg := getStr(obj, "error")
			result.Error = errMsg
			result.Events = append(result.Events, JsonEvent{EventType: "error", Text: errMsg, Raw: obj})
		}
	}
	return result
}

func ParseClaudeCodeJson(raw string) ParsedJsonOutput {
	result := ParsedJsonOutput{SchemaName: "claude-code"}
	for _, obj := range parseLine(raw) {
		result.RawLines = append(result.RawLines, obj)
		msgType := getStr(obj, "type")

		switch msgType {
		case "system":
			sub := getStr(obj, "subtype")
			if sub == "init" {
				result.SessionID = getStr(obj, "session_id")
			} else if sub == "api_retry" {
				result.Events = append(result.Events, JsonEvent{EventType: "system_retry", Raw: obj})
			}

		case "assistant":
			message := getMap(obj, "message")
			content := getSlice(message, "content")
			var texts []string
			for _, blk := range content {
				b, ok := blk.(map[string]interface{})
				if !ok {
					continue
				}
				if getStr(b, "type") == "text" {
					texts = append(texts, getStr(b, "text"))
				}
			}
			if len(texts) > 0 {
				text := strings.Join(texts, "\n")
				result.FinalText = text
				result.Events = append(result.Events, JsonEvent{EventType: "assistant", Text: text, Raw: obj})
			}
			usageRaw := getMap(message, "usage")
			if len(usageRaw) > 0 {
				result.Usage = usageFromMap(usageRaw)
			}

		case "stream_event":
			event := getMap(obj, "event")
			eventType := getStr(event, "type")
			switch eventType {
			case "content_block_delta":
				delta := getMap(event, "delta")
				deltaType := getStr(delta, "type")
				switch deltaType {
				case "text_delta":
					result.Events = append(result.Events, JsonEvent{EventType: "text_delta", Text: getStr(delta, "text"), Raw: obj})
				case "thinking_delta":
					result.Events = append(result.Events, JsonEvent{EventType: "thinking_delta", Thinking: getStr(delta, "thinking"), Raw: obj})
				case "input_json_delta":
					result.Events = append(result.Events, JsonEvent{EventType: "tool_input_delta", Text: getStr(delta, "partial_json"), Raw: obj})
				}
			case "content_block_start":
				cb := getMap(event, "content_block")
				cbType := getStr(cb, "type")
				switch cbType {
				case "thinking":
					result.Events = append(result.Events, JsonEvent{EventType: "thinking_start", Raw: obj})
				case "tool_use":
					result.Events = append(result.Events, JsonEvent{
						EventType: "tool_use_start",
						ToolCall:  &ToolCall{ID: getStr(cb, "id"), Name: getStr(cb, "name"), Arguments: ""},
						Raw:       obj,
					})
				}
			}

		case "tool_use":
			argsBytes, _ := json.Marshal(obj["tool_input"])
			tc := &ToolCall{ID: "", Name: getStr(obj, "tool_name"), Arguments: string(argsBytes)}
			result.Events = append(result.Events, JsonEvent{EventType: "tool_use", ToolCall: tc, Raw: obj})

		case "tool_result":
			tr := &ToolResult{
				ToolCallID: getStr(obj, "tool_use_id"),
				Content:    getStr(obj, "content"),
				IsError:    getBool(obj, "is_error"),
			}
			result.Events = append(result.Events, JsonEvent{EventType: "tool_result", ToolResult: tr, Raw: obj})

		case "result":
			sub := getStr(obj, "subtype")
			if sub == "success" {
				resText := getStr(obj, "result")
				if resText == "" {
					resText = result.FinalText
				}
				result.FinalText = resText
				result.CostUSD = getFloat(obj, "cost_usd")
				result.DurationMs = getInt(obj, "duration_ms")
				usageRaw := getMap(obj, "usage")
				if len(usageRaw) > 0 {
					result.Usage = usageFromMap(usageRaw)
				}
				result.Events = append(result.Events, JsonEvent{EventType: "result", Text: result.FinalText, Raw: obj})
			} else if sub == "error" {
				result.Error = getStr(obj, "error")
				result.Events = append(result.Events, JsonEvent{EventType: "error", Text: result.Error, Raw: obj})
			}
		}
	}
	return result
}

func ParseKimiJson(raw string) ParsedJsonOutput {
	result := ParsedJsonOutput{SchemaName: "kimi"}
	passthroughTypes := map[string]bool{
		"TurnBegin": true, "StepBegin": true, "StepInterrupted": true, "TurnEnd": true,
		"StatusUpdate": true, "HookTriggered": true, "HookResolved": true,
		"ApprovalRequest": true, "SubagentEvent": true, "ToolCallRequest": true,
	}
	for _, obj := range parseLine(raw) {
		result.RawLines = append(result.RawLines, obj)
		wireType := getStr(obj, "type")
		if passthroughTypes[wireType] {
			result.Events = append(result.Events, JsonEvent{EventType: strings.ToLower(wireType), Raw: obj})
			continue
		}
		role := getStr(obj, "role")
		switch role {
		case "assistant":
			contentVal := obj["content"]
			toolCalls := getSlice(obj, "tool_calls")
			switch cv := contentVal.(type) {
			case string:
				result.FinalText = cv
				result.Events = append(result.Events, JsonEvent{EventType: "assistant", Text: cv, Raw: obj})
			case []interface{}:
				var texts []string
				for _, part := range cv {
					p, ok := part.(map[string]interface{})
					if !ok {
						continue
					}
					partType := getStr(p, "type")
					switch partType {
					case "text":
						texts = append(texts, getStr(p, "text"))
					case "think":
						result.Events = append(result.Events, JsonEvent{EventType: "thinking", Thinking: getStr(p, "think"), Raw: obj})
					}
				}
				if len(texts) > 0 {
					text := strings.Join(texts, "\n")
					result.FinalText = text
					result.Events = append(result.Events, JsonEvent{EventType: "assistant", Text: text, Raw: obj})
				}
			}
			for _, tcData := range toolCalls {
				tcMap, ok := tcData.(map[string]interface{})
				if !ok {
					continue
				}
				fn := getMap(tcMap, "function")
				tc := &ToolCall{
					ID:        getStr(tcMap, "id"),
					Name:      getStr(fn, "name"),
					Arguments: getStr(fn, "arguments"),
				}
				result.Events = append(result.Events, JsonEvent{EventType: "tool_call", ToolCall: tc, Raw: obj})
			}

		case "tool":
			content := getSlice(obj, "content")
			var texts []string
			for _, part := range content {
				p, ok := part.(map[string]interface{})
				if !ok {
					continue
				}
				if getStr(p, "type") == "text" {
					text := getStr(p, "text")
					if !strings.HasPrefix(text, "<system>") {
						texts = append(texts, text)
					}
				}
			}
			tr := &ToolResult{
				ToolCallID: getStr(obj, "tool_call_id"),
				Content:    strings.Join(texts, "\n"),
			}
			result.Events = append(result.Events, JsonEvent{EventType: "tool_result", ToolResult: tr, Raw: obj})
		}
	}
	return result
}

func ParseJsonOutput(raw string, schema string) ParsedJsonOutput {
	switch schema {
	case "opencode":
		return ParseOpenCodeJson(raw)
	case "claude-code":
		return ParseClaudeCodeJson(raw)
	case "kimi":
		return ParseKimiJson(raw)
	default:
		return ParsedJsonOutput{SchemaName: schema, Error: fmt.Sprintf("unknown schema: %s", schema)}
	}
}

func RenderParsed(output ParsedJsonOutput) string {
	var parts []string
	for _, event := range output.Events {
		switch event.EventType {
		case "text", "assistant", "result":
			if event.Text != "" {
				parts = append(parts, event.Text)
			}
		case "thinking_delta", "thinking":
			if event.Thinking != "" {
				parts = append(parts, fmt.Sprintf("[thinking] %s", event.Thinking))
			}
		case "tool_use":
			if event.ToolCall != nil {
				parts = append(parts, fmt.Sprintf("[tool] %s", event.ToolCall.Name))
			}
		case "tool_result":
			if event.ToolResult != nil {
				parts = append(parts, fmt.Sprintf("[tool_result] %s", event.ToolResult.Content))
			}
		case "error":
			if event.Text != "" {
				parts = append(parts, fmt.Sprintf("[error] %s", event.Text))
			}
		}
	}
	if len(parts) > 0 {
		return strings.Join(parts, "\n")
	}
	return output.FinalText
}

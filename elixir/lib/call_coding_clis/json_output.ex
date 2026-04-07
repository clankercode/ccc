defmodule CallCodingClis.JsonOutput do
  defmodule ToolCall do
    defstruct id: "", name: "", arguments: ""
  end

  defmodule ToolResult do
    defstruct tool_call_id: "", content: "", is_error: false
  end

  defmodule JsonEvent do
    defstruct event_type: "", text: "", thinking: "", tool_call: nil, tool_result: nil, raw: %{}
  end

  defmodule ParsedJsonOutput do
    defstruct schema_name: "",
              events: [],
              final_text: "",
              session_id: "",
              error: "",
              usage: %{},
              cost_usd: 0.0,
              duration_ms: 0,
              raw_lines: []
  end

  @passthrough_types MapSet.new([
                       "TurnBegin",
                       "StepBegin",
                       "StepInterrupted",
                       "TurnEnd",
                       "StatusUpdate",
                       "HookTriggered",
                       "HookResolved",
                       "ApprovalRequest",
                       "SubagentEvent",
                       "ToolCallRequest"
                     ])

  def parse_opencode_json(raw_stdout) when is_binary(raw_stdout) do
    result = %ParsedJsonOutput{schema_name: "opencode"}

    raw_stdout
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce(result, fn line, acc ->
      line = String.trim(line)

      if line == "" do
        acc
      else
        case Jason.decode(line) do
          {:ok, obj} ->
            acc = %{acc | raw_lines: acc.raw_lines ++ [obj]}

            cond do
              Map.has_key?(obj, "response") ->
                text = obj["response"]

                %{
                  acc
                  | final_text: text,
                    events: acc.events ++ [%JsonEvent{event_type: "text", text: text, raw: obj}]
                }

              Map.has_key?(obj, "error") ->
                err = obj["error"]

                %{
                  acc
                  | error: err,
                    events: acc.events ++ [%JsonEvent{event_type: "error", text: err, raw: obj}]
                }

              true ->
                acc
            end

          {:error, _} ->
            acc
        end
      end
    end)
  end

  def parse_claude_code_json(raw_stdout) when is_binary(raw_stdout) do
    result = %ParsedJsonOutput{schema_name: "claude-code"}

    raw_stdout
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce(result, &reduce_claude_line/2)
  end

  defp reduce_claude_line(line, acc) do
    line = String.trim(line)

    if line == "" do
      acc
    else
      case Jason.decode(line) do
        {:ok, obj} ->
          acc = %{acc | raw_lines: acc.raw_lines ++ [obj]}
          msg_type = Map.get(obj, "type", "")
          apply_claude_event(msg_type, obj, acc)

        {:error, _} ->
          acc
      end
    end
  end

  defp apply_claude_event("system", obj, acc) do
    case Map.get(obj, "subtype", "") do
      "init" -> %{acc | session_id: Map.get(obj, "session_id", "")}
      "api_retry" -> append_event(acc, %JsonEvent{event_type: "system_retry", raw: obj})
      _ -> acc
    end
  end

  defp apply_claude_event("assistant", obj, acc) do
    message = Map.get(obj, "message", %{})
    content = Map.get(message, "content", [])

    texts =
      content
      |> Enum.filter(fn
        %{"type" => "text"} -> true
        _ -> false
      end)
      |> Enum.map(fn block -> Map.get(block, "text", "") end)

    acc =
      if texts != [] do
        text = Enum.join(texts, "\n")

        %{
          acc
          | final_text: text,
            events: acc.events ++ [%JsonEvent{event_type: "assistant", text: text, raw: obj}]
        }
      else
        acc
      end

    usage = Map.get(message, "usage")

    if usage do
      %{acc | usage: usage}
    else
      acc
    end
  end

  defp apply_claude_event("stream_event", obj, acc) do
    event = Map.get(obj, "event", %{})
    event_type = Map.get(event, "type", "")

    cond do
      event_type == "content_block_delta" ->
        delta = Map.get(event, "delta", %{})
        delta_type = Map.get(delta, "type", "")

        cond do
          delta_type == "text_delta" ->
            append_event(acc, %JsonEvent{
              event_type: "text_delta",
              text: Map.get(delta, "text", ""),
              raw: obj
            })

          delta_type == "thinking_delta" ->
            append_event(acc, %JsonEvent{
              event_type: "thinking_delta",
              thinking: Map.get(delta, "thinking", ""),
              raw: obj
            })

          delta_type == "input_json_delta" ->
            append_event(acc, %JsonEvent{
              event_type: "tool_input_delta",
              text: Map.get(delta, "partial_json", ""),
              raw: obj
            })

          true ->
            acc
        end

      event_type == "content_block_start" ->
        cb = Map.get(event, "content_block", %{})
        cb_type = Map.get(cb, "type", "")

        cond do
          cb_type == "thinking" ->
            append_event(acc, %JsonEvent{event_type: "thinking_start", raw: obj})

          cb_type == "tool_use" ->
            tc = %ToolCall{
              id: Map.get(cb, "id", ""),
              name: Map.get(cb, "name", ""),
              arguments: ""
            }

            append_event(acc, %JsonEvent{event_type: "tool_use_start", tool_call: tc, raw: obj})

          true ->
            acc
        end

      true ->
        acc
    end
  end

  defp apply_claude_event("tool_use", obj, acc) do
    tool_input = Map.get(obj, "tool_input", %{})
    tc = %ToolCall{name: Map.get(obj, "tool_name", ""), arguments: Jason.encode!(tool_input)}
    append_event(acc, %JsonEvent{event_type: "tool_use", tool_call: tc, raw: obj})
  end

  defp apply_claude_event("tool_result", obj, acc) do
    tr = %ToolResult{
      tool_call_id: Map.get(obj, "tool_use_id", ""),
      content: Map.get(obj, "content", ""),
      is_error: Map.get(obj, "is_error", false)
    }

    append_event(acc, %JsonEvent{event_type: "tool_result", tool_result: tr, raw: obj})
  end

  defp apply_claude_event("result", obj, acc) do
    case Map.get(obj, "subtype", "") do
      "success" ->
        result_text = Map.get(obj, "result", acc.final_text)

        %{
          acc
          | final_text: result_text,
            cost_usd: Map.get(obj, "cost_usd", 0.0),
            duration_ms: Map.get(obj, "duration_ms", 0),
            usage: Map.get(obj, "usage", acc.usage),
            events: acc.events ++ [%JsonEvent{event_type: "result", text: result_text, raw: obj}]
        }

      "error" ->
        err = Map.get(obj, "error", "")

        %{
          acc
          | error: err,
            events: acc.events ++ [%JsonEvent{event_type: "error", text: err, raw: obj}]
        }

      _ ->
        acc
    end
  end

  defp apply_claude_event(_, _, acc), do: acc

  defp append_event(acc, event) do
    %{acc | events: acc.events ++ [event]}
  end

  def parse_kimi_json(raw_stdout) when is_binary(raw_stdout) do
    result = %ParsedJsonOutput{schema_name: "kimi"}

    raw_stdout
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce(result, &reduce_kimi_line/2)
  end

  defp reduce_kimi_line(line, acc) do
    line = String.trim(line)

    if line == "" do
      acc
    else
      case Jason.decode(line) do
        {:ok, obj} ->
          acc = %{acc | raw_lines: acc.raw_lines ++ [obj]}
          apply_kimi_event(obj, acc)

        {:error, _} ->
          acc
      end
    end
  end

  defp apply_kimi_event(obj, acc) do
    wire_type = Map.get(obj, "type", "")

    if MapSet.member?(@passthrough_types, wire_type) do
      append_event(acc, %JsonEvent{event_type: String.downcase(wire_type), raw: obj})
    else
      role = Map.get(obj, "role", "")

      cond do
        role == "assistant" ->
          acc = parse_kimi_assistant_content(obj, acc)
          acc = parse_kimi_tool_calls(obj, acc)
          acc

        role == "tool" ->
          parse_kimi_tool_result(obj, acc)

        true ->
          acc
      end
    end
  end

  defp parse_kimi_assistant_content(obj, acc) do
    content = Map.get(obj, "content")

    cond do
      is_binary(content) ->
        %{
          acc
          | final_text: content,
            events: acc.events ++ [%JsonEvent{event_type: "assistant", text: content, raw: obj}]
        }

      is_list(content) ->
        {texts, acc} =
          Enum.reduce(content, {[], acc}, fn part, {texts, a} ->
            if is_map(part) do
              case Map.get(part, "type", "") do
                "text" ->
                  {[Map.get(part, "text", "") | texts], a}

                "think" ->
                  event = %JsonEvent{
                    event_type: "thinking",
                    thinking: Map.get(part, "think", ""),
                    raw: obj
                  }

                  {texts, %{a | events: a.events ++ [event]}}

                _ ->
                  {texts, a}
              end
            else
              {texts, a}
            end
          end)

        texts = Enum.reverse(texts)

        if texts != [] do
          text = Enum.join(texts, "\n")

          %{
            acc
            | final_text: text,
              events: acc.events ++ [%JsonEvent{event_type: "assistant", text: text, raw: obj}]
          }
        else
          acc
        end

      true ->
        acc
    end
  end

  defp parse_kimi_tool_calls(obj, acc) do
    tool_calls = Map.get(obj, "tool_calls")

    if is_list(tool_calls) do
      Enum.reduce(tool_calls, acc, fn tc_data, a ->
        fn_map = Map.get(tc_data, "function", %{})

        tc = %ToolCall{
          id: Map.get(tc_data, "id", ""),
          name: Map.get(fn_map, "name", ""),
          arguments: Map.get(fn_map, "arguments", "")
        }

        append_event(a, %JsonEvent{event_type: "tool_call", tool_call: tc, raw: obj})
      end)
    else
      acc
    end
  end

  defp parse_kimi_tool_result(obj, acc) do
    content = Map.get(obj, "content", [])

    texts =
      if is_list(content) do
        content
        |> Enum.filter(fn
          %{"type" => "text"} -> true
          _ -> false
        end)
        |> Enum.map(fn part -> Map.get(part, "text", "") end)
        |> Enum.reject(fn t -> String.starts_with?(t, "<system>") end)
      else
        []
      end

    tr = %ToolResult{
      tool_call_id: Map.get(obj, "tool_call_id", ""),
      content: Enum.join(texts, "\n")
    }

    append_event(acc, %JsonEvent{event_type: "tool_result", tool_result: tr, raw: obj})
  end

  def parse_json_output(raw_stdout, schema) when is_binary(raw_stdout) and is_binary(schema) do
    case schema do
      "opencode" -> parse_opencode_json(raw_stdout)
      "claude-code" -> parse_claude_code_json(raw_stdout)
      "kimi" -> parse_kimi_json(raw_stdout)
      _ -> %ParsedJsonOutput{schema_name: schema, error: "unknown schema: #{schema}"}
    end
  end

  def render_parsed(%ParsedJsonOutput{} = output) do
    parts =
      output.events
      |> Enum.reduce([], fn event, acc ->
        case event.event_type do
          t when t in ["text", "assistant", "result"] ->
            if event.text != "", do: acc ++ [event.text], else: acc

          t when t in ["thinking_delta", "thinking"] ->
            if event.thinking != "", do: acc ++ ["[thinking] #{event.thinking}"], else: acc

          "tool_use" ->
            if event.tool_call, do: acc ++ ["[tool] #{event.tool_call.name}"], else: acc

          "tool_result" ->
            if event.tool_result,
              do: acc ++ ["[tool_result] #{event.tool_result.content}"],
              else: acc

          "error" ->
            if event.text != "", do: acc ++ ["[error] #{event.text}"], else: acc

          _ ->
            acc
        end
      end)

    if parts != [], do: Enum.join(parts, "\n"), else: output.final_text
  end
end

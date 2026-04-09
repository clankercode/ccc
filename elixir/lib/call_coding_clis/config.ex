defmodule CallCodingClis.Config do
  alias CallCodingClis.Parser.{CccConfig, AliasDef}

  @config_dir_name "ccc"
  @config_file_name "config.toml"

  def load_config(path \\ nil)

  def load_config(nil) do
    default_config_paths()
    |> Enum.find_value(%CccConfig{}, fn candidate ->
      if File.exists?(candidate), do: load_from_file(candidate), else: nil
    end)
  end

  def load_config(path) when is_binary(path) do
    if File.exists?(path), do: load_from_file(path), else: %CccConfig{}
  end

  defp default_config_paths do
    paths =
      case System.get_env("XDG_CONFIG_HOME") do
        x when is_binary(x) and x != "" ->
          [Path.join([x, @config_dir_name, @config_file_name])]

        _ ->
          []
      end

    paths ++ [Path.join([System.user_home!(), ".config", @config_dir_name, @config_file_name])]
  end

  defp load_from_file(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> parse_toml()
        |> build_config()

      {:error, _} ->
        %CccConfig{}
    end
  rescue
    _ -> %CccConfig{}
  end

  defp build_config(data) when is_map(data) do
    config = %CccConfig{}

    config =
      case Map.get(data, "defaults") do
        d when is_map(d) ->
          %{
            config
            | default_runner: Map.get(d, "runner", config.default_runner),
              default_provider: Map.get(d, "provider", config.default_provider),
              default_model: Map.get(d, "model", config.default_model),
              default_thinking: parse_thinking(Map.get(d, "thinking"))
          }

        _ ->
          config
      end

    config =
      case Map.get(data, "abbreviations") do
        a when is_map(a) ->
          %{config | abbreviations: Map.new(a, fn {k, v} -> {to_string(k), to_string(v)} end)}

        _ ->
          config
      end

    case Map.get(data, "aliases") do
      a when is_map(a) ->
        aliases =
          Map.new(a, fn {name, defn} ->
            alias_def =
              if is_map(defn) do
                %AliasDef{
                  runner: Map.get(defn, "runner"),
                  thinking: parse_thinking(Map.get(defn, "thinking")),
                  provider: Map.get(defn, "provider"),
                  model: Map.get(defn, "model"),
                  agent: Map.get(defn, "agent")
                }
              else
                %AliasDef{}
              end

            {to_string(name), alias_def}
          end)

        %{config | aliases: aliases}

      _ ->
        config
    end
  end

  defp build_config(_), do: %CccConfig{}

  defp parse_thinking(nil), do: nil
  defp parse_thinking(v) when is_integer(v), do: v
  defp parse_thinking(v) when is_binary(v), do: String.to_integer(v)

  defp parse_toml(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
    |> Enum.reduce({%{}, [], nil}, fn line, {data, section_stack, current_section} ->
      cond do
        String.starts_with?(line, "[[") and String.ends_with?(line, "]]") ->
          {data, section_stack, nil}

        String.starts_with?(line, "[") and String.ends_with?(line, "]") ->
          section_name = line |> String.slice(1..-2//1) |> String.trim()
          {data, section_stack, section_name}

        true ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = key |> String.trim()
              parsed_value = parse_toml_value(String.trim(value))

              if current_section do
                parts = String.split(current_section, ".")
                {data, _} = put_nested(data, parts, key, parsed_value)
                {data, section_stack, current_section}
              else
                {Map.put(data, key, parsed_value), section_stack, current_section}
              end

            _ ->
              {data, section_stack, current_section}
          end
      end
    end)
    |> elem(0)
  end

  defp put_nested(data, [], key, value), do: {Map.put(data, key, value), data}

  defp put_nested(data, [head | rest], key, value) do
    existing = Map.get(data, head, %{})
    existing = if is_map(existing), do: existing, else: %{}
    {updated, _} = put_nested(existing, rest, key, value)
    {Map.put(data, head, updated), data}
  end

  defp parse_toml_value("\"" <> rest) do
    case String.split(rest, "\"", parts: 2) do
      [val, ""] -> val
      [val | _] -> val
      _ -> "\"" <> rest
    end
  end

  defp parse_toml_value(value) do
    cond do
      value == "true" -> true
      value == "false" -> false
      Regex.match?(~r/^-?\d+$/, value) -> String.to_integer(value)
      true -> value
    end
  end
end

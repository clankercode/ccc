defmodule CallCodingClis.Parser do
  defmodule RunnerInfo do
    defstruct binary: "", extra_args: [], thinking_flags: %{}, provider_flag: "", model_flag: ""
  end

  defmodule ParsedArgs do
    defstruct runner: nil, thinking: nil, provider: nil, model: nil, alias: nil, prompt: ""
  end

  defmodule AliasDef do
    defstruct runner: nil, thinking: nil, provider: nil, model: nil
  end

  defmodule CccConfig do
    defstruct default_runner: "oc",
              default_provider: "",
              default_model: "",
              default_thinking: nil,
              aliases: %{},
              abbreviations: %{}
  end

  @runner_selector_re ~r/^(?:oc|cc|c|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$/i
  @thinking_re ~r/^\+([0-4])$/
  @provider_model_re ~r/^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$/
  @model_re ~r/^:([a-zA-Z0-9._-]+)$/
  @alias_re ~r/^@([a-zA-Z0-9_-]+)$/

  def runner_registry do
    opencode = %RunnerInfo{
      binary: "opencode",
      extra_args: ["run"],
      thinking_flags: %{},
      provider_flag: "",
      model_flag: ""
    }

    claude = %RunnerInfo{
      binary: "claude",
      extra_args: [],
      thinking_flags: %{
        0 => ["--no-thinking"],
        1 => ["--thinking", "low"],
        2 => ["--thinking", "medium"],
        3 => ["--thinking", "high"],
        4 => ["--thinking", "max"]
      },
      provider_flag: "",
      model_flag: "--model"
    }

    kimi = %RunnerInfo{
      binary: "kimi",
      extra_args: [],
      thinking_flags: %{
        0 => ["--no-think"],
        1 => ["--think", "low"],
        2 => ["--think", "medium"],
        3 => ["--think", "high"],
        4 => ["--think", "max"]
      },
      provider_flag: "",
      model_flag: "--model"
    }

    codex = %RunnerInfo{
      binary: "codex",
      extra_args: [],
      thinking_flags: %{},
      provider_flag: "",
      model_flag: "--model"
    }

    crush = %RunnerInfo{
      binary: "crush",
      extra_args: [],
      thinking_flags: %{},
      provider_flag: "",
      model_flag: ""
    }

    %{
      "opencode" => opencode,
      "claude" => claude,
      "kimi" => kimi,
      "codex" => codex,
      "crush" => crush,
      "oc" => opencode,
      "cc" => claude,
      "c" => claude,
      "k" => kimi,
      "rc" => codex,
      "cr" => crush
    }
  end

  def parse_args(argv) when is_list(argv) do
    {parsed, positional} =
      Enum.reduce(argv, {%ParsedArgs{}, []}, fn token, {p, pos} ->
        cond do
          Regex.match?(@runner_selector_re, token) and p.runner == nil and pos == [] ->
            {%{p | runner: String.downcase(token)}, pos}

          Regex.match?(@thinking_re, token) and pos == [] ->
            [level] = Regex.run(@thinking_re, token, capture: :all_but_first)
            {%{p | thinking: String.to_integer(level)}, pos}

          (match = Regex.run(@provider_model_re, token)) != nil and pos == [] ->
            [_, provider, model] = match
            {%{p | provider: provider, model: model}, pos}

          (match = Regex.run(@model_re, token)) != nil and pos == [] ->
            [_, model] = match
            {%{p | model: model}, pos}

          (match = Regex.run(@alias_re, token)) != nil and p.alias == nil and pos == [] ->
            [_, alias_name] = match
            {%{p | alias: alias_name}, pos}

          true ->
            {p, pos ++ [token]}
        end
      end)

    %{parsed | prompt: Enum.join(positional, " ")}
  end

  def resolve_command(parsed, config \\ %CccConfig{})

  def resolve_command(%ParsedArgs{} = parsed, %CccConfig{} = config) do
    registry = runner_registry()
    runner_name = resolve_runner_name(parsed.runner, config)

    default_info = Map.get(registry, config.default_runner, Map.get(registry, "opencode"))
    info = Map.get(registry, runner_name, default_info)

    alias_def =
      if parsed.alias != nil do
        Map.get(config.aliases, parsed.alias)
      else
        nil
      end

    {_effective_runner_name, info} =
      if alias_def != nil and alias_def.runner != nil and parsed.runner == nil do
        ern = resolve_runner_name(alias_def.runner, config)
        {ern, Map.get(registry, ern, info)}
      else
        {runner_name, info}
      end

    argv = [info.binary | info.extra_args]

    effective_thinking = parsed.thinking

    effective_thinking =
      if effective_thinking == nil and alias_def != nil,
        do: alias_def.thinking,
        else: effective_thinking

    effective_thinking =
      if effective_thinking == nil, do: config.default_thinking, else: effective_thinking

    argv =
      if effective_thinking != nil do
        case Map.get(info.thinking_flags, effective_thinking) do
          nil -> argv
          flags -> argv ++ flags
        end
      else
        argv
      end

    effective_provider = parsed.provider

    effective_provider =
      if effective_provider == nil and alias_def != nil and alias_def.provider != nil,
        do: alias_def.provider,
        else: effective_provider

    effective_provider =
      if effective_provider == nil and config.default_provider != "",
        do: config.default_provider,
        else: effective_provider

    effective_model = parsed.model

    effective_model =
      if effective_model == nil and alias_def != nil and alias_def.model != nil,
        do: alias_def.model,
        else: effective_model

    effective_model =
      if effective_model == nil and config.default_model != "",
        do: config.default_model,
        else: effective_model

    argv =
      if effective_model != nil and effective_model != "" and info.model_flag != "" do
        argv ++ [info.model_flag, effective_model]
      else
        argv
      end

    env_overrides =
      if effective_provider != nil and effective_provider != "" do
        %{"CCC_PROVIDER" => effective_provider}
      else
        %{}
      end

    prompt = String.trim(parsed.prompt)

    if prompt == "" do
      {:error, "prompt must not be empty"}
    else
      {:ok, {argv ++ [prompt], env_overrides}}
    end
  end

  defp resolve_runner_name(nil, config), do: config.default_runner

  defp resolve_runner_name(name, config) do
    case Map.get(config.abbreviations, name) do
      nil -> name
      abbrev -> abbrev
    end
  end
end

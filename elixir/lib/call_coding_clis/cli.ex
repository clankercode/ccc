defmodule CallCodingClis.CLI do
  alias CallCodingClis.{CommandSpec, Config, PromptSpec, Runner}
  alias CallCodingClis.Parser

  def main(argv) do
    case argv do
      [] ->
        IO.write(
          :stderr,
          "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n"
        )

        System.halt(1)

      [prompt] ->
        spec =
          try do
            PromptSpec.build(prompt)
          rescue
            e in ArgumentError ->
              IO.write(:stderr, Exception.message(e) <> "\n")
              System.halt(1)
          end

        run_spec(spec)

      _ ->
        parsed = Parser.parse_args(argv)

        if String.trim(parsed.prompt) == "" do
          IO.write(:stderr, "prompt must not be empty\n")
          System.halt(1)
        end

        config = Config.load_config()

        case Parser.resolve_command(parsed, config) do
          {:ok, {resolved_argv, env_overrides}} ->
            spec = %CommandSpec{argv: resolved_argv, env: env_overrides}
            run_spec(spec)

          {:error, reason} ->
            IO.write(:stderr, reason <> "\n")
            System.halt(1)
        end
    end
  end

  defp run_spec(spec) do
    spec =
      case System.get_env("CCC_REAL_OPENCODE") do
        nil -> spec
        override -> %{spec | argv: [override | tl(spec.argv)]}
      end

    result = Runner.run(spec)

    if result.stdout != "", do: IO.write(result.stdout)
    if result.stderr != "", do: IO.write(:stderr, result.stderr)
    System.halt(result.exit_code)
  end
end

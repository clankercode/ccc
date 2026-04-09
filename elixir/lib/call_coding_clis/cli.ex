defmodule CallCodingClis.CLI do
  alias CallCodingClis.{CommandSpec, Config, Help, PromptSpec, Runner}
  alias CallCodingClis.Parser

  def main(argv) do
    case argv do
      [] ->
        Help.print_usage()
        System.halt(1)

      ["--help" | _] ->
        Help.print_help()
        System.halt(0)

      ["-h" | _] ->
        Help.print_help()
        System.halt(0)

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

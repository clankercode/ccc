defmodule CallCodingClis.CLI do
  alias CallCodingClis.{PromptSpec, Runner, CommandSpec}

  def main(argv) do
    case argv do
      [prompt] ->
        %CommandSpec{} =
          spec =
          try do
            PromptSpec.build(prompt)
          rescue
            e in ArgumentError ->
              IO.write(:stderr, Exception.message(e) <> "\n")
              System.halt(1)
          end

        spec =
          case System.get_env("CCC_REAL_OPENCODE") do
            nil -> spec
            override -> %{spec | argv: [override | tl(spec.argv)]}
          end

        result = Runner.run(spec)

        if result.stdout != "" do
          IO.write(result.stdout)
        end

        if result.stderr != "" do
          IO.write(:stderr, result.stderr)
        end

        System.halt(result.exit_code)

      _ ->
        IO.write(:stderr, "usage: ccc \"<Prompt>\"\n")
        System.halt(1)
    end
  end
end

defmodule CallCodingClis.MixProject do
  use Mix.Project

  def project do
    [
      app: :call_coding_clis,
      version: "0.1.0",
      elixir: "~> 1.17",
      escript: [main_module: CallCodingClis.CLI, name: "ccc"],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:jason, "~> 1.4"}]
  end

  def application, do: []
end

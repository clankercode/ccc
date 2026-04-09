defmodule CallCodingClis.Help do
  alias CallCodingClis.Parser

  @canonical_runners [
    {"opencode", "oc"},
    {"claude", "cc"},
    {"kimi", "k"},
    {"codex", "c/cx"},
    {"roocode", "rc"},
    {"crush", "cr"}
  ]

  @help_text """
  ccc — call coding CLIs

  Usage:
    ccc [controls...] "<Prompt>"
    ccc --help
    ccc -h

  Slots (in order):
    runner        Select which coding CLI to use (default: oc)
                  opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
    +thinking     Set thinking level: +0 (off) through +4 (max)
    :provider:model  Override provider and model
    @name         Use a named preset from config; if no preset exists, treat it as an agent

  Examples:
    ccc "Fix the failing tests"
    ccc oc "Refactor auth module"
    ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
    ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
    ccc k +4 "Debug the parser"
    ccc @reviewer "Audit the API boundary"
    ccc rc "Probe RooCode"
    ccc codex "Write a unit test"

  Config:
    ~/.config/ccc/config.toml  — default runner, presets, abbreviations
  """

  def runner_checklist do
    registry = Parser.runner_registry()

    lines =
      Enum.reduce(@canonical_runners, ["Runners:"], fn {name, _alias}, acc ->
        info = Map.get(registry, name)
        binary = if info, do: info.binary, else: name

        case System.find_executable(binary) do
          nil ->
            acc ++ ["  [-] #{String.pad_trailing(name, 10)} (#{binary})  not found"]

          _resolved ->
            version = get_version(binary)
            tag = if version != "", do: version, else: "found"
            acc ++ ["  [+] #{String.pad_trailing(name, 10)} (#{binary})  #{tag}"]
        end
      end)

    Enum.join(lines, "\n")
  end

  def print_help do
    IO.write(@help_text)
    IO.write("\n")
    IO.write(runner_checklist())
    IO.write("\n")
  end

  def print_usage do
    IO.write(:stderr, "usage: ccc [controls...] \"<Prompt>\"\n")
    IO.write(:stderr, runner_checklist())
    IO.write(:stderr, "\n")
  end

  defp get_version(binary) do
    try do
      {output, exit_code} = System.cmd(binary, ["--version"], stderr_to_stdout: true)
      if exit_code == 0, do: String.trim(output) |> String.split("\n") |> hd(), else: ""
    catch
      _, _ -> ""
    end
  end
end

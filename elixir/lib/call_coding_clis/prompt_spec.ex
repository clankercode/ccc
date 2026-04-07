defmodule CallCodingClis.PromptSpec do
  alias CallCodingClis.CommandSpec

  def build(prompt) when is_binary(prompt) do
    trimmed = String.trim(prompt)

    if trimmed == "" do
      raise ArgumentError, "prompt must not be empty"
    end

    %CommandSpec{argv: ["opencode", "run", trimmed]}
  end
end

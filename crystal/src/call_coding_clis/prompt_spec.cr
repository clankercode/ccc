def build_prompt_spec(prompt : String) : CommandSpec
  trimmed = prompt.strip
  raise ArgumentError.new("prompt must not be empty") if trimmed.empty?
  CommandSpec.new(["opencode", "run", trimmed])
end

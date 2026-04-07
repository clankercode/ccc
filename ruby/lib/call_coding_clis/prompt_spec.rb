# frozen_string_literal: true

module CallCodingClis
  def self.build_prompt_spec(prompt)
    normalized = prompt.strip
    raise ArgumentError, "prompt must not be empty" if normalized.empty?
    CommandSpec.new(argv: ["opencode", "run", normalized])
  end
end

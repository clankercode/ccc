# frozen_string_literal: true

module CallCodingClis
  def self.build_prompt_spec(prompt)
    normalized = prompt.strip
    raise ArgumentError, "prompt must not be empty" if normalized.empty?
    CommandSpec.new(argv: ["opencode", "run", normalized])
  end

  def self.build_v2_spec(argv, config: nil)
    parsed = Parser.parse_args(argv)
    warnings = []
    cmd_argv, env = Parser.resolve_command(parsed, config, warnings: warnings)
    warnings.each { |warning| warn warning }
    CommandSpec.new(argv: cmd_argv, env: env)
  end
end

# frozen_string_literal: true

module CallCodingClis
  CommandSpec = Struct.new(:argv, :stdin_text, :cwd, :env, keyword_init: true) do
    def initialize(argv:, stdin_text: nil, cwd: nil, env: {})
      super
    end
  end
end

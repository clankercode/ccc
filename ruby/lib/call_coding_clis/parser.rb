# frozen_string_literal: true

module CallCodingClis
  module Parser
    RunnerInfo = Struct.new(:binary, :extra_args, :thinking_flags, :provider_flag, :model_flag, :agent_flag, keyword_init: true)
    ParsedArgs = Struct.new(:runner, :thinking, :provider, :model, :alias_name, :prompt, keyword_init: true) do
      def initialize(runner: nil, thinking: nil, provider: nil, model: nil, alias_name: nil, prompt: "")
        super
      end
    end
    AliasDef = Struct.new(:runner, :thinking, :provider, :model, :agent, keyword_init: true)
    CccConfig = Struct.new(:default_runner, :default_provider, :default_model, :default_thinking, :aliases, :abbreviations, keyword_init: true) do
      def initialize(default_runner: "oc", default_provider: "", default_model: "", default_thinking: nil, aliases: {}, abbreviations: {})
        super
      end
    end

    RUNNER_REGISTRY = {}

    def self.register_defaults!
      return unless RUNNER_REGISTRY.empty?

      RUNNER_REGISTRY["opencode"] = RunnerInfo.new(
        binary: "opencode",
        extra_args: ["run"],
        thinking_flags: {},
        provider_flag: "",
        model_flag: "",
        agent_flag: "--agent"
      )
      RUNNER_REGISTRY["claude"] = RunnerInfo.new(
        binary: "claude",
        extra_args: [],
        thinking_flags: {
          0 => ["--no-thinking"],
          1 => ["--thinking", "low"],
          2 => ["--thinking", "medium"],
          3 => ["--thinking", "high"],
          4 => ["--thinking", "max"]
        },
        provider_flag: "",
        model_flag: "--model",
        agent_flag: "--agent"
      )
      RUNNER_REGISTRY["kimi"] = RunnerInfo.new(
        binary: "kimi",
        extra_args: [],
        thinking_flags: {
          0 => ["--no-think"],
          1 => ["--think", "low"],
          2 => ["--think", "medium"],
          3 => ["--think", "high"],
          4 => ["--think", "max"]
        },
        provider_flag: "",
        model_flag: "--model",
        agent_flag: "--agent"
      )
      RUNNER_REGISTRY["codex"] = RunnerInfo.new(
        binary: "codex",
        extra_args: [],
        thinking_flags: {},
        provider_flag: "",
        model_flag: "--model",
        agent_flag: ""
      )
      RUNNER_REGISTRY["roocode"] = RunnerInfo.new(
        binary: "roocode",
        extra_args: [],
        thinking_flags: {},
        provider_flag: "",
        model_flag: "",
        agent_flag: ""
      )
      RUNNER_REGISTRY["crush"] = RunnerInfo.new(
        binary: "crush",
        extra_args: [],
        thinking_flags: {},
        provider_flag: "",
        model_flag: "",
        agent_flag: ""
      )

      RUNNER_REGISTRY["oc"] = RUNNER_REGISTRY["opencode"]
      RUNNER_REGISTRY["cc"] = RUNNER_REGISTRY["claude"]
      RUNNER_REGISTRY["c"] = RUNNER_REGISTRY["codex"]
      RUNNER_REGISTRY["cx"] = RUNNER_REGISTRY["codex"]
      RUNNER_REGISTRY["k"] = RUNNER_REGISTRY["kimi"]
      RUNNER_REGISTRY["rc"] = RUNNER_REGISTRY["roocode"]
      RUNNER_REGISTRY["cr"] = RUNNER_REGISTRY["crush"]
    end

    register_defaults!

    RUNNER_SELECTOR_RE = /\A(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)\z/i
    THINKING_RE = /\A\+([0-4])\z/
    PROVIDER_MODEL_RE = /\A:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)\z/
    MODEL_RE = /\A:([a-zA-Z0-9._-]+)\z/
    ALIAS_RE = /\A@([a-zA-Z0-9_-]+)\z/

    def self.parse_args(argv)
      parsed = ParsedArgs.new
      positional = []

      argv.each do |token|
        if RUNNER_SELECTOR_RE.match?(token) && parsed.runner.nil? && positional.empty?
          parsed.runner = token.downcase
        elsif positional.empty? && (m = THINKING_RE.match(token))
          parsed.thinking = Integer(m[1])
        elsif positional.empty? && (m = PROVIDER_MODEL_RE.match(token))
          parsed.provider = m[1]
          parsed.model = m[2]
        elsif positional.empty? && (m = MODEL_RE.match(token))
          parsed.model = m[1]
        elsif (m = ALIAS_RE.match(token)) && parsed.alias_name.nil? && positional.empty?
          parsed.alias_name = m[1]
        else
          positional << token
        end
      end

      parsed.prompt = positional.join(" ")
      parsed
    end

    def self.resolve_runner_name(name, config)
      return config.default_runner if name.nil?
      config.abbreviations.fetch(name, name)
    end

    def self.resolve_command(parsed, config = nil, warnings: nil)
      config ||= CccConfig.new
      warnings ||= []

      runner_name = resolve_runner_name(parsed.runner, config)
      info = RUNNER_REGISTRY.fetch(runner_name) {
        RUNNER_REGISTRY.fetch(config.default_runner, RUNNER_REGISTRY["opencode"])
      }

      alias_def = nil
      if parsed.alias_name && config.aliases.key?(parsed.alias_name)
        alias_def = config.aliases[parsed.alias_name]
      end

      effective_runner_name = runner_name
      if alias_def && alias_def.runner && parsed.runner.nil?
        effective_runner_name = resolve_runner_name(alias_def.runner, config)
        info = RUNNER_REGISTRY.fetch(effective_runner_name, info)
      end

      argv = [info.binary, *info.extra_args]

      effective_thinking = parsed.thinking
      if effective_thinking.nil? && alias_def && !alias_def.thinking.nil?
        effective_thinking = alias_def.thinking
      end
      effective_thinking = config.default_thinking if effective_thinking.nil?
      if !effective_thinking.nil? && info.thinking_flags.key?(effective_thinking)
        argv.concat(info.thinking_flags[effective_thinking])
      end

      effective_provider = parsed.provider
      if effective_provider.nil? && alias_def && alias_def.provider
        effective_provider = alias_def.provider
      end
      effective_provider = config.default_provider if effective_provider.nil?

      effective_model = parsed.model
      if effective_model.nil? && alias_def && alias_def.model
        effective_model = alias_def.model
      end
      effective_model = config.default_model if effective_model.nil?

      if effective_model && !effective_model.empty? && !info.model_flag.empty?
        argv.concat([info.model_flag, effective_model])
      end

      effective_agent = nil
      agent_source = nil
      if parsed.alias_name
        if alias_def && alias_def.agent && !alias_def.agent.to_s.empty?
          effective_agent = alias_def.agent
          agent_source = "@#{parsed.alias_name}"
        elsif alias_def.nil?
          effective_agent = parsed.alias_name
          agent_source = "@#{parsed.alias_name}"
        end
      end

      if effective_agent && !effective_agent.to_s.empty?
        if info.agent_flag && !info.agent_flag.empty?
          argv.concat([info.agent_flag, effective_agent])
        else
          warning_suffix = (alias_def && alias_def.agent && alias_def.agent.to_s != parsed.alias_name) ? " (agent #{effective_agent})" : ""
          warnings << "warning: runner \"#{effective_runner_name}\" does not support agents; ignoring #{agent_source}#{warning_suffix}"
        end
      end

      env_overrides = {}
      if effective_provider && !effective_provider.empty?
        env_overrides["CCC_PROVIDER"] = effective_provider
      end

      prompt = parsed.prompt.strip
      raise ArgumentError, "prompt must not be empty" if prompt.empty?

      argv << prompt
      [argv, env_overrides]
    end
  end
end

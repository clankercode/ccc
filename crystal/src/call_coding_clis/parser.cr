struct RunnerInfo
  getter binary : String
  getter extra_args : Array(String)
  getter thinking_flags : Hash(Int32, Array(String))
  getter provider_flag : String
  getter model_flag : String
  getter agent_flag : String

  def initialize(
    @binary : String,
    @extra_args : Array(String) = [] of String,
    @thinking_flags : Hash(Int32, Array(String)) = Hash(Int32, Array(String)).new,
    @provider_flag : String = "",
    @model_flag : String = "",
    @agent_flag : String = ""
  )
  end
end

struct ParsedArgs
  property runner : String?
  property thinking : Int32?
  property provider : String?
  property model : String?
  property alias : String?
  property prompt : String

  def initialize(
    @runner : String? = nil,
    @thinking : Int32? = nil,
    @provider : String? = nil,
    @model : String? = nil,
    @alias : String? = nil,
    @prompt : String = ""
  )
  end
end

struct AliasDef
  property runner : String?
  property thinking : Int32?
  property provider : String?
  property model : String?
  property agent : String?

  def initialize(
    @runner : String? = nil,
    @thinking : Int32? = nil,
    @provider : String? = nil,
    @model : String? = nil,
    @agent : String? = nil
  )
  end
end

struct CccConfig
  property default_runner : String
  property default_provider : String
  property default_model : String
  property default_thinking : Int32?
  property aliases : Hash(String, AliasDef)
  property abbreviations : Hash(String, String)

  def initialize(
    @default_runner : String = "oc",
    @default_provider : String = "",
    @default_model : String = "",
    @default_thinking : Int32? = nil,
    @aliases : Hash(String, AliasDef) = Hash(String, AliasDef).new,
    @abbreviations : Hash(String, String) = Hash(String, String).new
  )
  end
end

module RunnerRegistry
  @@registry : Hash(String, RunnerInfo) = build_registry

  private def self.build_registry : Hash(String, RunnerInfo)
    reg = Hash(String, RunnerInfo).new

    oc = RunnerInfo.new(
      binary: "opencode",
      extra_args: ["run"],
      thinking_flags: Hash(Int32, Array(String)).new,
      provider_flag: "",
      model_flag: "",
      agent_flag: "--agent"
    )
    cc = RunnerInfo.new(
      binary: "claude",
      extra_args: [] of String,
      thinking_flags: {
        0 => ["--no-thinking"],
        1 => ["--thinking", "low"],
        2 => ["--thinking", "medium"],
        3 => ["--thinking", "high"],
        4 => ["--thinking", "max"],
      },
      provider_flag: "",
      model_flag: "--model",
      agent_flag: "--agent"
    )
    k = RunnerInfo.new(
      binary: "kimi",
      extra_args: [] of String,
      thinking_flags: {
        0 => ["--no-think"],
        1 => ["--think", "low"],
        2 => ["--think", "medium"],
        3 => ["--think", "high"],
        4 => ["--think", "max"],
      },
      provider_flag: "",
      model_flag: "--model",
      agent_flag: "--agent"
    )
    codex = RunnerInfo.new(
      binary: "codex",
      extra_args: [] of String,
      thinking_flags: Hash(Int32, Array(String)).new,
      provider_flag: "",
      model_flag: "--model",
      agent_flag: ""
    )
    roocode = RunnerInfo.new(
      binary: "roocode",
      extra_args: [] of String,
      thinking_flags: Hash(Int32, Array(String)).new,
      provider_flag: "",
      model_flag: "--model",
      agent_flag: ""
    )
    cr = RunnerInfo.new(
      binary: "crush",
      extra_args: [] of String,
      thinking_flags: Hash(Int32, Array(String)).new,
      provider_flag: "",
      model_flag: "",
      agent_flag: ""
    )

    reg["opencode"] = oc
    reg["claude"] = cc
    reg["kimi"] = k
    reg["codex"] = codex
    reg["roocode"] = roocode
    reg["crush"] = cr

    reg["oc"] = oc
    reg["cc"] = cc
    reg["c"] = codex
    reg["cx"] = codex
    reg["k"] = k
    reg["rc"] = roocode
    reg["cr"] = cr

    reg
  end

  def self.[](key : String) : RunnerInfo
    @@registry[key]
  end

  def self.[]?(key : String) : RunnerInfo?
    @@registry[key]?
  end
end

RUNNER_SELECTOR_RE = /^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$/i
THINKING_RE = /^\+([0-4])$/
PROVIDER_MODEL_RE = /^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$/
MODEL_RE = /^:([a-zA-Z0-9._-]+)$/
ALIAS_RE = /^@([a-zA-Z0-9_-]+)$/

def parse_args(argv : Array(String)) : ParsedArgs
  parsed = ParsedArgs.new
  positional = [] of String

  argv.each do |token|
    if RUNNER_SELECTOR_RE.matches?(token) && parsed.runner.nil? && positional.empty?
      parsed.runner = token.downcase
    elsif THINKING_RE.matches?(token) && positional.empty?
      m = THINKING_RE.match(token)
      parsed.thinking = m.not_nil![1].to_i32 if m
    elsif PROVIDER_MODEL_RE.matches?(token) && positional.empty?
      m = PROVIDER_MODEL_RE.match(token)
      if m
        parsed.provider = m[1]
        parsed.model = m[2]
      end
    elsif MODEL_RE.matches?(token) && positional.empty?
      m = MODEL_RE.match(token)
      parsed.model = m.not_nil![1] if m
    elsif ALIAS_RE.matches?(token) && parsed.alias.nil? && positional.empty?
      m = ALIAS_RE.match(token)
      parsed.alias = m.not_nil![1] if m
    else
      positional << token
    end
  end

  parsed.prompt = positional.join(" ")
  parsed
end

def resolve_runner_name(name : String?, config : CccConfig) : String
  return config.default_runner if name.nil?
  abbrev = config.abbreviations[name]?
  return abbrev if abbrev
  name
end

def resolve_command(parsed : ParsedArgs, config : CccConfig = CccConfig.new, warnings : Array(String)? = nil) : {Array(String), Hash(String, String)}
  runner_name = resolve_runner_name(parsed.runner, config)

  info = RunnerRegistry[runner_name]? ||
    RunnerRegistry[config.default_runner]? ||
    RunnerRegistry["opencode"].not_nil!

  warnings ||= [] of String
  alias_def : AliasDef? = nil
  if (a = parsed.alias) && (ad = config.aliases[a]?)
    alias_def = ad
  end

  effective_runner_name = info.binary
  if alias_def && (ar = alias_def.runner) && parsed.runner.nil?
    if (ri = RunnerRegistry[resolve_runner_name(ar, config)]?)
      info = ri
      effective_runner_name = info.binary
    end
  end

  argv = [info.binary] + info.extra_args

  effective_thinking = parsed.thinking
  if effective_thinking.nil? && alias_def && (at = alias_def.thinking)
    effective_thinking = at
  end
  if effective_thinking.nil?
    effective_thinking = config.default_thinking
  end
  if (et = effective_thinking) && (flags = info.thinking_flags[et]?)
    argv += flags
  end

  effective_provider = parsed.provider
  if effective_provider.nil? && alias_def && (ap = alias_def.provider)
    effective_provider = ap
  end
  if effective_provider.nil?
    ep = config.default_provider
    effective_provider = ep.empty? ? nil : ep
  end

  effective_model = parsed.model
  if effective_model.nil? && alias_def && (am = alias_def.model)
    effective_model = am
  end
  if effective_model.nil?
    em = config.default_model
    effective_model = em.empty? ? nil : em
  end

  if (em = effective_model) && !info.model_flag.empty?
    argv += [info.model_flag, em]
  end

  effective_agent : String? = nil
  if alias_def && (agent = alias_def.agent) && !agent.empty?
    effective_agent = agent
  elsif (a = parsed.alias) && alias_def.nil?
    effective_agent = a
  end

  if (agent = effective_agent) && !agent.empty?
    if info.agent_flag.empty?
      warnings << %(warning: runner "#{effective_runner_name}" does not support agents; ignoring @#{agent})
    else
      argv += [info.agent_flag, agent]
    end
  end

  env_overrides = Hash(String, String).new
  if ep = effective_provider
    env_overrides["CCC_PROVIDER"] = ep
  end

  prompt = parsed.prompt.strip
  raise ArgumentError.new("prompt must not be empty") if prompt.empty?

  argv << prompt
  {argv, env_overrides}
end

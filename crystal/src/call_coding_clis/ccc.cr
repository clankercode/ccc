require "./runner"
require "./prompt_spec"
require "./parser"
require "./config"

if ARGV.empty?
  STDERR.puts %(usage: ccc [<runner>] [+<thinking>] [:<provider>:<model>] [@<alias>] <Prompt>)
  exit 1
end

begin
  if ARGV.size == 1
    spec = build_prompt_spec(ARGV[0])
  else
    config = load_config
    parsed = parse_args(ARGV.to_a)
    argv, env_overrides = resolve_command(parsed, config)
    if override = ENV["CCC_REAL_OPENCODE"]?
      argv[0] = override
    end
    spec = CommandSpec.new(argv, env: env_overrides)
  end
rescue ex : ArgumentError
  STDERR.puts ex.message
  exit 1
end

runner = Runner.new
result = runner.run(spec)

print(result.stdout) unless result.stdout.empty?
STDERR.print(result.stderr) unless result.stderr.empty?
exit(result.exit_code)

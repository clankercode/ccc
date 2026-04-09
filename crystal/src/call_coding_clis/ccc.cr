require "./runner"
require "./prompt_spec"
require "./parser"
require "./config"
require "./help"

if ARGV.empty?
  print_usage
  exit 1
end

if ARGV == ["--help"] || ARGV == ["-h"]
  print_help
  exit 0
end

begin
  if ARGV.size == 1
    spec = build_prompt_spec(ARGV[0])
    if override = ENV["CCC_REAL_OPENCODE"]?
      spec = CommandSpec.new([override] + spec.argv[1..], stdin_text: spec.stdin_text, cwd: spec.cwd, env: spec.env)
    end
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

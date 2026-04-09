require "./runner"
require "./parser"
require "./config"

USAGE = "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\""

if ARGV.empty?
  STDERR.puts(USAGE)
  exit 1
end

if ARGV == ["--help"] || ARGV == ["-h"]
  puts("ccc — call coding CLIs")
  puts
  puts(USAGE)
  exit 0
end

begin
  config = load_config
  parsed = parse_args(ARGV.to_a)
  if parsed.prompt.strip.empty?
    STDERR.puts("prompt must not be empty")
    exit 1
  end
  argv, env_overrides = resolve_command(parsed, config)
  if override = ENV["CCC_REAL_OPENCODE"]?
    argv[0] = override
  end
  spec = CommandSpec.new(argv, env: env_overrides)
rescue ex : ArgumentError
  STDERR.puts ex.message
  exit 1
end

runner = Runner.new
result = runner.run(spec)

print(result.stdout) unless result.stdout.empty?
STDERR.print(result.stderr) unless result.stderr.empty?
exit(result.exit_code)

require "./runner"
require "./prompt_spec"

if ARGV.size != 1
  STDERR.puts %(usage: ccc "<Prompt>")
  exit 1
end

begin
  spec = build_prompt_spec(ARGV[0])
rescue ex : ArgumentError
  STDERR.puts ex.message
  exit 1
end

if override = ENV["CCC_REAL_OPENCODE"]?
  spec.argv[0] = override
end

runner = Runner.new
result = runner.run(spec)

print(result.stdout) unless result.stdout.empty?
STDERR.print(result.stderr) unless result.stderr.empty?
exit(result.exit_code)

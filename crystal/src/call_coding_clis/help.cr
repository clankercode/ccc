require "./parser"

CANONICAL_RUNNERS = [
  {"opencode", "oc"},
  {"claude", "cc"},
  {"kimi", "k"},
  {"codex", "rc"},
  {"crush", "cr"},
]

HELP_TEXT = <<-HELP
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @alias        Use a named preset from config

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations
HELP

private def get_version(binary : String) : String
  begin
    process = Process.new(
      binary, ["--version"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    output = ""
    spawn do
      output = process.output.gets_to_end
    end
    select
    when process.wait
      process.error.gets_to_end
    when timeout(3.seconds)
      process.terminate
      return ""
    end
    if process.exit_code == 0
      line = output.strip.split("\n")[0]?
      return line if line && !line.empty?
    end
  rescue ex
  end
  ""
end

def runner_checklist : String
  lines = ["Runners:"]
  CANONICAL_RUNNERS.each do |(name, alias_name)|
    info = RunnerRegistry[name]?
    binary = info ? info.binary : name
    found = Process.find_executable(binary)
    if found
      version = get_version(binary)
      tag = version.empty? ? "found" : version
      lines << "  [+] %-10s (%s)  %s" % {name, binary, tag}
    else
      lines << "  [-] %-10s (%s)  not found" % {name, binary}
    end
  end
  lines.join("\n")
end

def print_help
  puts(HELP_TEXT)
  puts
  puts(runner_checklist)
end

def print_usage
  STDERR.puts(%(usage: ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"))
  STDERR.puts(runner_checklist)
end

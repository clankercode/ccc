# frozen_string_literal: true

require_relative "parser"

module CallCodingClis
  module Help
    CANONICAL_RUNNERS = [
      ["opencode", "oc"],
      ["claude", "cc"],
      ["kimi", "k"],
      ["codex", "c/cx"],
      ["roocode", "rc"],
      ["crush", "cr"]
    ].freeze

    HELP_TEXT = <<~HELP
      ccc — call coding CLIs

      Usage:
        ccc [controls...] "<Prompt>"
        ccc --help
        ccc -h

      Slots (in order):
        runner        Select which coding CLI to use (default: oc)
                      opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
        +thinking     Set thinking level: +0 (off) through +4 (max)
        :provider:model  Override provider and model
        @name         Use a named preset from config; if no preset exists, treat it as an agent

      Examples:
        ccc "Fix the failing tests"
        ccc oc "Refactor auth module"
        ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
        ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
        ccc k +4 "Debug the parser"
        ccc @reviewer "Audit the API boundary"
        ccc codex "Write a unit test"

      Config:
        ~/.config/ccc/config.toml  — default runner, presets, abbreviations
    HELP

    def self.get_version(binary)
      require "open3"
      require "timeout"
      stdout, _, status = Timeout.timeout(3) do
        Open3.capture3(binary, "--version")
      end
      return "" unless status.success? && !stdout.strip.empty?
      stdout.strip.split("\n", 2).first
    rescue Errno::ENOENT, Errno::EACCES, Timeout::Error
      ""
    end

    def self.runner_checklist
      lines = ["Runners:"]
      CANONICAL_RUNNERS.each do |name, _alias|
        info = Parser::RUNNER_REGISTRY[name]
        binary = info&.binary || name
        found = system("which", binary, out: File::NULL, err: File::NULL)
        if found
          version = get_version(binary)
          tag = version.empty? ? "found" : version
          lines << "  [+] #{name.ljust(10)} (#{binary})  #{tag}"
        else
          lines << "  [-] #{name.ljust(10)} (#{binary})  not found"
        end
      end
      lines.join("\n")
    end

    def self.print_help
      $stdout.puts HELP_TEXT
      $stdout.puts
      $stdout.puts runner_checklist
    end

    def self.print_usage
      $stderr.puts 'usage: ccc [controls...] "<Prompt>"'
      $stderr.puts runner_checklist
    end
  end
end

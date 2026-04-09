USAGE = "usage: ccc [controls...] \"<Prompt>\""

HELP_TEXT = <<-HELP
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
  ccc c "Write a unit test"
  ccc rc "Route to roocode"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
HELP

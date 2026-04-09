require "spec"
require "../src/call_coding_clis/help"

describe "help text" do
  it "uses the name slot and agent fallback wording" do
    USAGE.should eq(%(usage: ccc [controls...] "<Prompt>"))
    HELP_TEXT.should contain("[@name]")
    HELP_TEXT.should contain("if no preset exists, treat it as an agent")
    HELP_TEXT.should contain("presets, abbreviations")
    HELP_TEXT.should contain("codex (c/cx), roocode (rc), crush (cr)")
    HELP_TEXT.should contain("ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer \"Add tests\"")
    HELP_TEXT.should contain("ccc c +4 :openai:gpt-5.4-mini @agent \"Debug the parser\"")
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis"

class TestParser < Minitest::Test
  def test_parse_prompt_only
    parsed = CallCodingClis::Parser.parse_args(["fix the tests"])
    assert_nil parsed.runner
    assert_nil parsed.thinking
    assert_nil parsed.provider
    assert_nil parsed.model
    assert_nil parsed.alias_name
    assert_equal "fix the tests", parsed.prompt
  end

  def test_parse_runner_selector
    parsed = CallCodingClis::Parser.parse_args(["claude", "hello"])
    assert_equal "claude", parsed.runner
    assert_equal "hello", parsed.prompt
  end

  def test_parse_thinking_flag
    parsed = CallCodingClis::Parser.parse_args(["+3", "do stuff"])
    assert_equal 3, parsed.thinking
    assert_equal "do stuff", parsed.prompt
  end

  def test_parse_provider_model
    parsed = CallCodingClis::Parser.parse_args([":anthropic:claude-3.5", "prompt"])
    assert_equal "anthropic", parsed.provider
    assert_equal "claude-3.5", parsed.model
    assert_equal "prompt", parsed.prompt
  end

  def test_parse_model_only
    parsed = CallCodingClis::Parser.parse_args([":gpt-4o", "prompt"])
    assert_nil parsed.provider
    assert_equal "gpt-4o", parsed.model
    assert_equal "prompt", parsed.prompt
  end

  def test_parse_alias
    parsed = CallCodingClis::Parser.parse_args(["@fast", "prompt"])
    assert_equal "fast", parsed.alias_name
    assert_equal "prompt", parsed.prompt
  end

  def test_parse_full_combo
    parsed = CallCodingClis::Parser.parse_args(["claude", "+2", ":anthropic:opus", "@fast", "fix it"])
    assert_equal "claude", parsed.runner
    assert_equal 2, parsed.thinking
    assert_equal "anthropic", parsed.provider
    assert_equal "opus", parsed.model
    assert_equal "fast", parsed.alias_name
    assert_equal "fix it", parsed.prompt
  end

  def test_parse_runner_abbreviation_oc
    parsed = CallCodingClis::Parser.parse_args(["oc", "prompt"])
    assert_equal "oc", parsed.runner
  end

  def test_parse_runner_abbreviation_cc
    parsed = CallCodingClis::Parser.parse_args(["cc", "prompt"])
    assert_equal "cc", parsed.runner
  end

  def test_parse_runner_abbreviation_c
    parsed = CallCodingClis::Parser.parse_args(["c", "prompt"])
    assert_equal "c", parsed.runner
  end

  def test_parse_runner_abbreviation_cx
    parsed = CallCodingClis::Parser.parse_args(["cx", "prompt"])
    assert_equal "cx", parsed.runner
  end

  def test_parse_runner_case_insensitive
    parsed = CallCodingClis::Parser.parse_args(["Claude", "prompt"])
    assert_equal "claude", parsed.runner
  end

  def test_parse_positional_after_non_positional
    parsed = CallCodingClis::Parser.parse_args(["+1", "fix", "tests"])
    assert_equal 1, parsed.thinking
    assert_equal "fix tests", parsed.prompt
  end

  def test_parse_runner_only_once
    parsed = CallCodingClis::Parser.parse_args(["claude", "oc", "prompt"])
    assert_equal "claude", parsed.runner
    assert_equal "oc prompt", parsed.prompt
  end

  def test_resolve_default_runner
    parsed = CallCodingClis::Parser.parse_args(["hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["opencode", "run", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_claude_runner
    parsed = CallCodingClis::Parser.parse_args(["claude", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["claude", "hello"], argv
  end

  def test_resolve_thinking_flags_claude
    parsed = CallCodingClis::Parser.parse_args(["claude", "+2", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["claude", "--thinking", "enabled", "--effort", "medium", "hello"], argv
  end

  def test_resolve_thinking_flags_kimi
    parsed = CallCodingClis::Parser.parse_args(["kimi", "+0", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["kimi", "--no-thinking", "hello"], argv
  end

  def test_resolve_model_flag_claude
    parsed = CallCodingClis::Parser.parse_args(["claude", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["claude", "--model", "gpt-4o", "hello"], argv
  end

  def test_resolve_model_flag_codex
    parsed = CallCodingClis::Parser.parse_args(["codex", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["codex", "exec", "--model", "gpt-4o", "hello"], argv
  end

  def test_resolve_model_flag_codex_via_c
    parsed = CallCodingClis::Parser.parse_args(["c", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["codex", "exec", "--model", "gpt-4o", "hello"], argv
  end

  def test_resolve_model_flag_codex_via_cx
    parsed = CallCodingClis::Parser.parse_args(["cx", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["codex", "exec", "--model", "gpt-4o", "hello"], argv
  end

  def test_resolve_no_model_flag_opencode
    parsed = CallCodingClis::Parser.parse_args(["oc", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["opencode", "run", "hello"], argv
  end

  def test_resolve_no_model_flag_crush
    parsed = CallCodingClis::Parser.parse_args(["crush", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["crush", "hello"], argv
  end

  def test_resolve_no_model_flag_roocode
    parsed = CallCodingClis::Parser.parse_args(["rc", ":gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["roocode", "hello"], argv
  end

  def test_resolve_name_falls_back_to_agent_for_opencode
    parsed = CallCodingClis::Parser.parse_args(["@reviewer", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["opencode", "run", "--agent", "reviewer", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_name_uses_agent_flag_for_claude
    parsed = CallCodingClis::Parser.parse_args(["claude", "@reviewer", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["claude", "--agent", "reviewer", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_name_uses_agent_flag_for_kimi
    parsed = CallCodingClis::Parser.parse_args(["kimi", "@reviewer", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["kimi", "--agent", "reviewer", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_provider_env
    parsed = CallCodingClis::Parser.parse_args([":anthropic:gpt-4o", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal "anthropic", env["CCC_PROVIDER"]
  end

  def test_resolve_empty_prompt_error
    parsed = CallCodingClis::Parser.parse_args([])
    assert_raises(ArgumentError) do
      CallCodingClis::Parser.resolve_command(parsed)
    end
  end

  def test_resolve_empty_prompt_error_message
    parsed = CallCodingClis::Parser.parse_args([])
    err = assert_raises(ArgumentError) do
      CallCodingClis::Parser.resolve_command(parsed)
    end
    assert_equal "prompt must not be empty", err.message
  end

  def test_resolve_config_defaults
    parsed = CallCodingClis::Parser.parse_args(["hello"])
    config = CallCodingClis::Parser::CccConfig.new(
      default_runner: "claude",
      default_provider: "anthropic",
      default_model: "opus",
      default_thinking: 3
    )
    argv, env = CallCodingClis::Parser.resolve_command(parsed, config)
    assert_equal "claude", argv[0]
    assert_includes argv, "--thinking"
    assert_includes argv, "enabled"
    assert_includes argv, "--effort"
    assert_includes argv, "high"
    assert_includes argv, "--model"
    assert_includes argv, "opus"
    assert_equal "anthropic", env["CCC_PROVIDER"]
  end

  def test_resolve_alias
    parsed = CallCodingClis::Parser.parse_args(["@fast", "hello"])
    config = CallCodingClis::Parser::CccConfig.new(
      aliases: {
        "fast" => CallCodingClis::Parser::AliasDef.new(
          runner: "claude",
          thinking: 4,
          provider: "anthropic",
          model: "opus"
        )
      }
    )
    argv, env = CallCodingClis::Parser.resolve_command(parsed, config)
    assert_equal "claude", argv[0]
    assert_includes argv, "--thinking"
    assert_includes argv, "enabled"
    assert_includes argv, "--effort"
    assert_includes argv, "max"
    assert_includes argv, "--model"
    assert_includes argv, "opus"
    assert_equal "anthropic", env["CCC_PROVIDER"]
    assert_equal "hello", argv.last
  end

  def test_resolve_alias_agent
    parsed = CallCodingClis::Parser.parse_args(["@fast", "hello"])
    config = CallCodingClis::Parser::CccConfig.new(
      aliases: {
        "fast" => CallCodingClis::Parser::AliasDef.new(
          agent: "specialist"
        )
      }
    )
    argv, env = CallCodingClis::Parser.resolve_command(parsed, config)
    assert_equal ["opencode", "run", "--agent", "specialist", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_alias_runner_overridden_by_explicit
    parsed = CallCodingClis::Parser.parse_args(["kimi", "@fast", "hello"])
    config = CallCodingClis::Parser::CccConfig.new(
      aliases: {
        "fast" => CallCodingClis::Parser::AliasDef.new(runner: "claude")
      }
    )
    argv, _env = CallCodingClis::Parser.resolve_command(parsed, config)
    assert_equal "kimi", argv[0]
  end

  def test_resolve_unknown_name_falls_back_to_agent
    parsed = CallCodingClis::Parser.parse_args(["@nonexistent", "hello"])
    argv, env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal ["opencode", "run", "--agent", "nonexistent", "hello"], argv
    assert_equal({}, env)
  end

  def test_resolve_name_warning_for_unsupported_runner
    parsed = CallCodingClis::Parser.parse_args(["rc", "@reviewer", "hello"])
    warnings = []
    argv, env = CallCodingClis::Parser.resolve_command(parsed, nil, warnings: warnings)
    assert_equal ["roocode", "hello"], argv
    assert_equal({}, env)
    assert_equal ['warning: runner "rc" does not support agents; ignoring @reviewer'], warnings
  end

  def test_resolve_name_warning_for_codex_runner
    parsed = CallCodingClis::Parser.parse_args(["c", "@reviewer", "hello"])
    warnings = []
    argv, env = CallCodingClis::Parser.resolve_command(parsed, nil, warnings: warnings)
    assert_equal ["codex", "exec", "hello"], argv
    assert_equal({}, env)
    assert_equal ['warning: runner "c" does not support agents; ignoring @reviewer'], warnings
  end

  def test_resolve_abbreviation_via_config
    parsed = CallCodingClis::Parser.parse_args(["oc", "hello"])
    config = CallCodingClis::Parser::CccConfig.new(
      abbreviations: { "oc" => "claude" }
    )
    argv, _env = CallCodingClis::Parser.resolve_command(parsed, config)
    assert_equal "claude", argv[0]
  end

  def test_runner_registry_has_abbreviations
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["oc"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["opencode"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["cc"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["claude"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["c"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["codex"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["cx"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["codex"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["k"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["kimi"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["rc"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["roocode"]
    assert_equal CallCodingClis::Parser::RUNNER_REGISTRY["cr"],
                 CallCodingClis::Parser::RUNNER_REGISTRY["crush"]
  end

  def test_config_struct_defaults
    config = CallCodingClis::Parser::CccConfig.new
    assert_equal "oc", config.default_runner
    assert_equal "", config.default_provider
    assert_equal "", config.default_model
    assert_nil config.default_thinking
    assert_equal({}, config.aliases)
    assert_equal({}, config.abbreviations)
  end

  def test_parse_multiple_words_as_prompt
    parsed = CallCodingClis::Parser.parse_args(["fix", "the", "tests"])
    assert_equal "fix the tests", parsed.prompt
  end

  def test_parse_thinking_zero
    parsed = CallCodingClis::Parser.parse_args(["+0", "hello"])
    assert_equal 0, parsed.thinking
  end

  def test_parse_thinking_four
    parsed = CallCodingClis::Parser.parse_args(["+4", "hello"])
    assert_equal 4, parsed.thinking
  end

  def test_parse_thinking_rejects_five
    parsed = CallCodingClis::Parser.parse_args(["+5", "hello"])
    assert_nil parsed.thinking
    assert_equal "+5 hello", parsed.prompt
  end

  def test_resolve_whitespaced_prompt_stripped
    parsed = CallCodingClis::Parser.parse_args(["  hello  "])
    argv, _env = CallCodingClis::Parser.resolve_command(parsed)
    assert_equal "hello", argv.last
  end
end

class TestConfig < Minitest::Test
  def test_load_config_missing_file
    config = CallCodingClis::Config.load_config("/nonexistent/path/config.toml")
    assert_equal "oc", config.default_runner
    assert_equal({}, config.aliases)
  end

  def test_load_config_from_file
    require "tempfile"
    file = Tempfile.new(["ccc_test", ".toml"])
    file.write(<<~TOML)
      [defaults]
      runner = "claude"
      provider = "anthropic"
      model = "opus"
      thinking = 3

      [abbreviations]
      my = "claude"

      [aliases.fast]
      runner = "claude"
      thinking = 4
      provider = "anthropic"
      model = "opus"
      agent = "specialist"
    TOML
    file.close

    config = CallCodingClis::Config.load_config(file.path)
    assert_equal "claude", config.default_runner
    assert_equal "anthropic", config.default_provider
    assert_equal "opus", config.default_model
    assert_equal 3, config.default_thinking
    assert_equal({ "my" => "claude" }, config.abbreviations)
    assert_equal "claude", config.aliases["fast"].runner
    assert_equal 4, config.aliases["fast"].thinking
    assert_equal "anthropic", config.aliases["fast"].provider
    assert_equal "opus", config.aliases["fast"].model
    assert_equal "specialist", config.aliases["fast"].agent
  ensure
    file.unlink
  end

  def test_load_config_partial
    require "tempfile"
    file = Tempfile.new(["ccc_test", ".toml"])
    file.write(<<~TOML)
      [defaults]
      runner = "kimi"
    TOML
    file.close

    config = CallCodingClis::Config.load_config(file.path)
    assert_equal "kimi", config.default_runner
    assert_equal "", config.default_provider
  ensure
    file.unlink
  end
end

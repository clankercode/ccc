# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis"

class TestPromptSpec < Minitest::Test
  def test_normal_prompt
    spec = CallCodingClis.build_prompt_spec("Fix the tests")
    assert_equal ["opencode", "run", "Fix the tests"], spec.argv
  end

  def test_trimming
    spec = CallCodingClis.build_prompt_spec("  hello  ")
    assert_equal ["opencode", "run", "hello"], spec.argv
  end

  def test_rejects_empty
    assert_raises(ArgumentError) do
      CallCodingClis.build_prompt_spec("")
    end
  end

  def test_rejects_whitespace_only
    assert_raises(ArgumentError) do
      CallCodingClis.build_prompt_spec("   \t\n  ")
    end
  end

  def test_error_message
    err = assert_raises(ArgumentError) { CallCodingClis.build_prompt_spec("") }
    assert_equal "prompt must not be empty", err.message
  end

  def test_returns_command_spec
    spec = CallCodingClis.build_prompt_spec("do stuff")
    assert_instance_of CallCodingClis::CommandSpec, spec
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis"

class TestCommandSpec < Minitest::Test
  def test_construction_with_required_args
    spec = CallCodingClis::CommandSpec.new(argv: ["opencode", "run", "hello"])
    assert_equal ["opencode", "run", "hello"], spec.argv
  end

  def test_defaults
    spec = CallCodingClis::CommandSpec.new(argv: ["echo"])
    assert_nil spec.stdin_text
    assert_nil spec.cwd
    assert_equal({}, spec.env)
  end

  def test_all_fields
    spec = CallCodingClis::CommandSpec.new(
      argv: ["cmd"],
      stdin_text: "input",
      cwd: "/tmp",
      env: { "FOO" => "bar" }
    )
    assert_equal "input", spec.stdin_text
    assert_equal "/tmp", spec.cwd
    assert_equal({ "FOO" => "bar" }, spec.env)
  end

  def test_keyword_init_required
    assert_raises(ArgumentError) do
      CallCodingClis::CommandSpec.new
    end
  end

  def test_to_h
    spec = CallCodingClis::CommandSpec.new(argv: ["a"], stdin_text: "x")
    h = spec.to_h
    assert_equal ["a"], h[:argv]
    assert_equal "x", h[:stdin_text]
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis"

class TestCompletedRun < Minitest::Test
  def test_construction
    run = CallCodingClis::CompletedRun.new(
      argv: ["echo", "hi"],
      exit_code: 0,
      stdout: "hi\n",
      stderr: ""
    )
    assert_equal ["echo", "hi"], run.argv
    assert_equal 0, run.exit_code
    assert_equal "hi\n", run.stdout
    assert_equal "", run.stderr
  end

  def test_equality
    a = CallCodingClis::CompletedRun.new(argv: ["x"], exit_code: 1, stdout: "out", stderr: "err")
    b = CallCodingClis::CompletedRun.new(argv: ["x"], exit_code: 1, stdout: "out", stderr: "err")
    assert_equal a, b
  end

  def test_inequality
    a = CallCodingClis::CompletedRun.new(argv: ["x"], exit_code: 0, stdout: "", stderr: "")
    b = CallCodingClis::CompletedRun.new(argv: ["x"], exit_code: 1, stdout: "", stderr: "")
    refute_equal a, b
  end

  def test_inspect
    run = CallCodingClis::CompletedRun.new(argv: ["cmd"], exit_code: 0, stdout: "", stderr: "")
    assert_match(/CompletedRun/, run.inspect)
  end
end

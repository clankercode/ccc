# frozen_string_literal: true

require "minitest/autorun"
require "call_coding_clis"

class TestRunner < Minitest::Test
  def test_run_with_fake_executor
    fake_spec = CallCodingClis::CommandSpec.new(argv: ["echo", "hello"])
    fake_result = CallCodingClis::CompletedRun.new(
      argv: ["echo", "hello"],
      exit_code: 0,
      stdout: "hello\n",
      stderr: ""
    )
    runner = CallCodingClis::Runner.new(
      executor: ->(_spec) { fake_result }
    )
    result = runner.run(fake_spec)
    assert_equal 0, result.exit_code
    assert_equal "hello\n", result.stdout
    assert_equal "", result.stderr
  end

  def test_stream_with_fake_executor
    received = []
    runner = CallCodingClis::Runner.new(
      stream_executor: ->(_spec, block) {
        block&.call("stdout", "chunk1")
        block&.call("stderr", "chunk2")
        CallCodingClis::CompletedRun.new(
          argv: ["cmd"],
          exit_code: 0,
          stdout: "chunk1",
          stderr: "chunk2"
        )
      }
    )
    spec = CallCodingClis::CommandSpec.new(argv: ["cmd"])
    result = runner.stream(spec) { |ch, txt| received << [ch, txt] }
    assert_equal [["stdout", "chunk1"], ["stderr", "chunk2"]], received
    assert_equal 0, result.exit_code
  end

  def test_argv_snapshot_isolation
    argv = ["echo", "hello"]
    spec = CallCodingClis::CommandSpec.new(argv: argv)
    fake_result = CallCodingClis::CompletedRun.new(
      argv: ["echo", "hello"],
      exit_code: 0,
      stdout: "",
      stderr: ""
    )
    runner = CallCodingClis::Runner.new(
      executor: ->(s) {
        CallCodingClis::CompletedRun.new(
          argv: s.argv.dup,
          exit_code: 0,
          stdout: "",
          stderr: ""
        )
      }
    )
    result = runner.run(spec)
    refute_same result.argv, spec.argv
    assert_equal spec.argv, result.argv
  end

  def test_run_with_echo
    spec = CallCodingClis::CommandSpec.new(argv: ["echo", "hello"])
    runner = CallCodingClis::Runner.new
    result = runner.run(spec)
    assert_equal 0, result.exit_code
    assert_equal "hello\n", result.stdout
    assert_equal ["echo", "hello"], result.argv
  end

  def test_startup_failure
    spec = CallCodingClis::CommandSpec.new(argv: ["nonexistent_binary_xyz"])
    runner = CallCodingClis::Runner.new
    result = runner.run(spec)
    assert_equal 1, result.exit_code
    assert_match(/failed to start nonexistent_binary_xyz/, result.stderr)
    assert_equal "", result.stdout
  end

  def test_startup_failure_in_stream
    spec = CallCodingClis::CommandSpec.new(argv: ["nonexistent_binary_xyz"])
    runner = CallCodingClis::Runner.new
    received = []
    result = runner.stream(spec) { |ch, txt| received << [ch, txt] }
    assert_equal 1, result.exit_code
    assert_match(/failed to start nonexistent_binary_xyz/, result.stderr)
  end

  def test_exit_code_forwarding_nil_maps_to_1
    spec = CallCodingClis::CommandSpec.new(argv: ["nonexistent_binary_xyz"])
    runner = CallCodingClis::Runner.new
    result = runner.run(spec)
    assert_equal 1, result.exit_code
  end

  def test_env_merging
    spec = CallCodingClis::CommandSpec.new(
      argv: ["ruby", "-e", "puts ENV['CCC_TEST_VAR']"],
      env: { "CCC_TEST_VAR" => "from_spec" }
    )
    runner = CallCodingClis::Runner.new
    result = runner.run(spec)
    assert_equal "from_spec\n", result.stdout
    assert_equal 0, result.exit_code
  end
end

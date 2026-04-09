# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"
require_relative "../lib/call_coding_clis"

class TestCccCli < Minitest::Test
  CCC_BIN = File.expand_path("../bin/ccc", __dir__)
  RUBY_DIR = File.expand_path("..", __dir__)

  def run_ccc(*args, env: {})
    cmd = [RbConfig.ruby, CCC_BIN, *args]
    out, status = Open3.capture2e(ENV.to_h.merge(env), *cmd, chdir: RUBY_DIR)
    [out, status.exitstatus || 1]
  end

  def test_usage_with_no_args
    output, status = run_ccc
    assert_match(/usage: ccc/, output)
    assert_includes output, "[@name]"
    refute_equal 0, status
  end

  def test_help_mentions_name_slot
    output, status = run_ccc("--help")
    assert_equal 0, status
    assert_includes output, "[@name]"
    assert_includes output, "if no preset exists, treat it as an agent"
    assert_includes output, "codex (c/cx), roocode (rc)"
  end

  def test_two_args_joined_as_prompt
    Dir.mktmpdir do |tmp|
      stub = File.join(tmp, "opencode")
      File.write(stub, <<~SH)
        #!/bin/sh
        if [ "$1" != "run" ]; then exit 9; fi
        shift
        printf 'opencode run %s\n' "$*"
      SH
      File.chmod(0o755, stub)

      env = { "PATH" => "#{tmp}:#{ENV['PATH']}" }
      output, status = run_ccc("hello", "world", env: env)
      assert_equal "opencode run hello world\n", output
      assert_equal 0, status
    end
  end

  def test_empty_prompt
    output, status = run_ccc("")
    assert_match(/prompt must not be empty/, output)
    refute_equal 0, status
  end

  def test_whitespace_only_prompt
    output, status = run_ccc("   ")
    assert_match(/prompt must not be empty/, output)
    refute_equal 0, status
  end

  def test_happy_path
    Dir.mktmpdir do |tmp|
      stub = File.join(tmp, "opencode")
      File.write(stub, <<~SH)
        #!/bin/sh
        if [ "$1" != "run" ]; then exit 9; fi
        shift
        printf 'opencode run %s\n' "$1"
      SH
      File.chmod(0o755, stub)

      env = { "PATH" => "#{tmp}:#{ENV['PATH']}" }
      output, status = run_ccc("Fix the failing tests", env: env)
      assert_equal "opencode run Fix the failing tests\n", output
      assert_equal 0, status
    end
  end

  def test_agent_warning_for_unsupported_runner
    Dir.mktmpdir do |tmp|
      stub = File.join(tmp, "codex")
      File.write(stub, <<~SH)
        #!/bin/sh
        printf 'codex %s\n' "$*"
      SH
      File.chmod(0o755, stub)

      config_dir = File.join(tmp, ".config", "ccc")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "config.toml"), <<~TOML)
        [defaults]
        runner = "codex"
      TOML

      env = {
        "PATH" => "#{tmp}:#{ENV['PATH']}",
        "HOME" => tmp
      }
      output, status = run_ccc("@reviewer", "hello", env: env)
      assert_equal 0, status
      assert_includes output, 'warning: runner "codex" does not support agents; ignoring @reviewer'
      assert_includes output, "codex hello"
    end
  end

  def test_exit_code_forwarding
    Dir.mktmpdir do |tmp|
      stub = File.join(tmp, "opencode")
      File.write(stub, <<~SH)
        #!/bin/sh
        if [ "$1" != "run" ]; then exit 9; fi
        exit 42
      SH
      File.chmod(0o755, stub)

      env = { "PATH" => "#{tmp}:#{ENV['PATH']}" }
      _output, status = run_ccc("anything", env: env)
      assert_equal 42, status
    end
  end

  def test_ccc_real_opencode_env
    Dir.mktmpdir do |tmp|
      real_stub = File.join(tmp, "my_real_opencode")
      File.write(real_stub, <<~SH)
        #!/bin/sh
        printf 'real: %s\n' "$*"
      SH
      File.chmod(0o755, real_stub)

      env = {
        "PATH" => "#{tmp}:#{ENV['PATH']}",
        "CCC_REAL_OPENCODE" => real_stub
      }
      output, status = run_ccc("hello", env: env)
      assert_equal "real: run hello\n", output
      assert_equal 0, status
    end
  end

  def test_nonexistent_binary_stderr
    Dir.mktmpdir do |tmp|
      empty_path = "#{tmp}/empty"
      Dir.mkdir(empty_path)
      output, status = run_ccc("test", env: { "PATH" => empty_path })
      assert_match(/failed to start/, output)
      refute_equal 0, status
    end
  end
end

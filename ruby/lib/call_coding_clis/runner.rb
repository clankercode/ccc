# frozen_string_literal: true

require "open3"

module CallCodingClis
  class Runner
    def initialize(executor: nil, stream_executor: nil)
      @executor = executor || method(:default_run)
      @stream_executor = stream_executor || method(:default_stream)
    end

    def run(spec)
      @executor.call(spec)
    end

    def stream(spec, &block)
      @stream_executor.call(spec, block)
    end

    private

    def merged_env(overrides)
      ENV.to_h.merge(overrides)
    end

    def default_run(spec)
      opts = {}
      env = nil
      opts[:stdin_data] = spec.stdin_text unless spec.stdin_text.nil?
      opts[:chdir] = spec.cwd if spec.cwd
      env = merged_env(spec.env) unless spec.env.empty?
      stdout, stderr, status = if env
        Open3.capture3(env, *spec.argv, **opts)
      else
        Open3.capture3(*spec.argv, **opts)
      end
      CompletedRun.new(
        argv: spec.argv.dup,
        exit_code: status.exitstatus || 1,
        stdout: stdout,
        stderr: stderr
      )
    rescue Errno::ENOENT, Errno::EACCES => e
      CompletedRun.new(
        argv: spec.argv.dup,
        exit_code: 1,
        stdout: "",
        stderr: "failed to start #{spec.argv[0]}: #{e.message}\n"
      )
    end

    def default_stream(spec, block)
      opts = {}
      env = nil
      opts[:chdir] = spec.cwd if spec.cwd
      env = merged_env(spec.env) unless spec.env.empty?
      stdin_w, stdout_r, stderr_r, wait_thr = if env
        Open3.popen3(env, *spec.argv, **opts)
      else
        Open3.popen3(*spec.argv, **opts)
      end
      stdin_w.close

      stdout_buf = Thread.new { stdout_r.read }
      stderr_buf = Thread.new { stderr_r.read }

      stdout_text = stdout_buf.value
      stderr_text = stderr_buf.value

      stdout_r.close
      stderr_r.close

      block&.call("stdout", stdout_text) if stdout_text && !stdout_text.empty?
      block&.call("stderr", stderr_text) if stderr_text && !stderr_text.empty?

      CompletedRun.new(
        argv: spec.argv.dup,
        exit_code: wait_thr.value.exitstatus || 1,
        stdout: stdout_text.to_s,
        stderr: stderr_text.to_s
      )
    rescue Errno::ENOENT, Errno::EACCES => e
      block&.call("stderr", "failed to start #{spec.argv[0]}: #{e.message}\n")
      CompletedRun.new(
        argv: spec.argv.dup,
        exit_code: 1,
        stdout: "",
        stderr: "failed to start #{spec.argv[0]}: #{e.message}\n"
      )
    ensure
      [stdin_w, stdout_r, stderr_r].each { |io| io&.close }
    end
  end
end

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

    def command_with_env(spec)
      spec.env.empty? ? spec.argv : [merged_env(spec.env), *spec.argv]
    end

    def default_run(spec)
      opts = {}
      opts[:stdin_data] = spec.stdin_text unless spec.stdin_text.nil?
      opts[:chdir] = spec.cwd if spec.cwd
      stdout, stderr, status = Open3.capture3(*command_with_env(spec), **opts)
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
      stdin_w = nil
      stdout_r = nil
      stderr_r = nil

      opts = {}
      opts[:chdir] = spec.cwd if spec.cwd
      stdin_w, stdout_r, stderr_r, wait_thr = Open3.popen3(*command_with_env(spec), **opts)

      stdin_w.write(spec.stdin_text) if spec.stdin_text
      stdin_w.close

      stdout_text = Thread.new { stdout_r.read }.value
      stderr_text = Thread.new { stderr_r.read }.value

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
      [stdin_w, stdout_r, stderr_r].each { |io| io&.close unless io&.closed? }
    end
  end
end

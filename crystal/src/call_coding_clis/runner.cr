struct CommandSpec
  getter argv : Array(String)
  getter stdin_text : String?
  getter cwd : String?
  getter env : Hash(String, String)

  def initialize(@argv : Array(String), @stdin_text : String? = nil, @cwd : String? = nil, @env : Hash(String, String) = Hash(String, String).new)
  end
end

struct CompletedRun
  getter argv : Array(String)
  getter exit_code : Int32
  getter stdout : String
  getter stderr : String

  def initialize(@argv : Array(String), @exit_code : Int32, @stdout : String, @stderr : String)
  end
end

class Runner
  @run_executor : Proc(CommandSpec, CompletedRun)

  def initialize(run_executor : Proc(CommandSpec, CompletedRun)? = nil)
    @run_executor = run_executor || ->default_run(CommandSpec)
  end

  def run(spec : CommandSpec) : CompletedRun
    @run_executor.call(spec)
  end

  def stream(spec : CommandSpec, &on_event : String, String -> Nil) : CompletedRun
    result = run(spec)
    on_event.call("stdout", result.stdout) unless result.stdout.empty?
    on_event.call("stderr", result.stderr) unless result.stderr.empty?
    result
  end

  private def default_run(spec : CommandSpec) : CompletedRun
    argv = spec.argv
    return CompletedRun.new(argv, 1, "", "argv must not be empty\n") if argv.empty?

    binary = argv[0]

    begin
      process = Process.new(
        binary,
        argv[1..],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe,
        chdir: spec.cwd,
        env: spec.env
      )

      if text = spec.stdin_text
        process.input.print(text)
      end
      process.input.close

      ch = Channel(String).new(2)

      spawn { ch.send(process.output.gets_to_end) }
      spawn { ch.send(process.error.gets_to_end) }

      stdout_data = ch.receive
      stderr_data = ch.receive

      status = process.wait

      CompletedRun.new(
        argv: argv,
        exit_code: status.exit_code || 1,
        stdout: stdout_data,
        stderr: stderr_data
      )
    rescue ex
      CompletedRun.new(
        argv: argv,
        exit_code: 1,
        stdout: "",
        stderr: "failed to start #{binary}: #{ex.message}\n"
      )
    end
  end
end

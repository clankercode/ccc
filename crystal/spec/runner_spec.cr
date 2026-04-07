require "spec"
require "../src/call_coding_clis/runner"
require "../src/call_coding_clis/prompt_spec"

describe "build_prompt_spec" do
  it "returns correct argv for valid prompt" do
    spec = build_prompt_spec("hello")
    spec.argv.should eq(["opencode", "run", "hello"])
  end

  it "trims whitespace from prompt" do
    spec = build_prompt_spec("  foo  ")
    spec.argv.should eq(["opencode", "run", "foo"])
  end

  it "rejects empty prompt" do
    expect_raises(ArgumentError, /empty/) do
      build_prompt_spec("")
    end
  end

  it "rejects whitespace-only prompt" do
    expect_raises(ArgumentError, /empty/) do
      build_prompt_spec("   ")
    end
  end
end

describe "Runner" do
  it "uses injected executor" do
    mock = Proc(CommandSpec, CompletedRun).new { |_spec|
      CompletedRun.new(
        argv: ["echo", "hello"],
        exit_code: 0,
        stdout: "hello\n",
        stderr: ""
      )
    }
    runner = Runner.new(mock)
    result = runner.run(build_prompt_spec("test"))
    result.exit_code.should eq(0)
    result.stdout.should eq("hello\n")
    result.stderr.should eq("")
  end

  it "reports startup failure for nonexistent binary" do
    runner = Runner.new
    spec = CommandSpec.new(["/nonexistent_binary_xyz"])
    result = runner.run(spec)
    result.stderr.should match(/^failed to start \/nonexistent_binary_xyz:/)
    result.exit_code.should eq(1)
  end

  it "fires stream callbacks for stdout and stderr" do
    mock = Proc(CommandSpec, CompletedRun).new { |_spec|
      CompletedRun.new(
        argv: ["echo", "hello"],
        exit_code: 0,
        stdout: "hello\n",
        stderr: "err\n"
      )
    }
    runner = Runner.new(mock)
    events = [] of {String, String}
    result = runner.stream(build_prompt_spec("test")) do |stream, data|
      events << {stream, data}
    end
    result.exit_code.should eq(0)
    events.should eq([{"stdout", "hello\n"}, {"stderr", "err\n"}])
  end

  it "returns empty stdout and stderr for successful run" do
    mock = Proc(CommandSpec, CompletedRun).new { |_spec|
      CompletedRun.new(
        argv: ["true"],
        exit_code: 0,
        stdout: "",
        stderr: ""
      )
    }
    runner = Runner.new(mock)
    result = runner.run(build_prompt_spec("test"))
    result.exit_code.should eq(0)
    result.stdout.should eq("")
    result.stderr.should eq("")
  end
end

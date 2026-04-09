require "spec"

ROOT = File.expand_path("..", __DIR__)

class CrystalCliSpecState
  @@binary_path = ""

  def self.binary_path : String
    @@binary_path
  end

  def self.binary_path=(path : String)
    @@binary_path = path
  end
end

def build_cli_binary : String
  build_dir = File.join(Dir.tempdir, "ccc_crystal_cli_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(build_dir)
  binary = File.join(build_dir, "ccc")

  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(
    "crystal",
    ["build", "src/call_coding_clis/ccc.cr", "-o", binary],
    chdir: ROOT,
    output: stdout,
    error: stderr
  )

  unless status.success?
    raise "failed to build Crystal CLI: #{stderr.to_s}"
  end

  binary
end

def run_cli(args : Array(String), env : Hash(String, String) = Hash(String, String).new)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(
    CrystalCliSpecState.binary_path,
    args,
    chdir: ROOT,
    env: env,
    output: stdout,
    error: stderr
  )
  {stdout.to_s, stderr.to_s, status}
end

describe "ccc cli" do
  before_all do
    CrystalCliSpecState.binary_path = build_cli_binary
  end

  it "prints help text with the name slot" do
    stdout, stderr, status = run_cli(["--help"])
    status.success?.should be_true
    stdout.should contain("[@name]")
    stdout.should contain("if no preset exists, treat it as an agent")
    stderr.should be_empty
  end

  it "warns when the selected runner does not support agents" do
    tmpdir = File.join(Dir.tempdir, "ccc_crystal_cli_env_#{Random.rand(1_000_000)}")
    Dir.mkdir_p(tmpdir)
    begin
      bin_dir = File.join(tmpdir, "bin")
      xdg_dir = File.join(tmpdir, "xdg", "ccc")
      Dir.mkdir_p(bin_dir)
      Dir.mkdir_p(xdg_dir)

      stub = File.join(bin_dir, "roocode")
      File.write(stub, <<-SH)
        #!/bin/sh
        printf 'roocode %s\\n' "$*"
      SH
      File.chmod(stub, 0o755)

      File.write(File.join(xdg_dir, "config.toml"), <<-CFG)
        [defaults]
        runner = rc
        CFG

      env = {
        "PATH" => "#{bin_dir}:#{ENV["PATH"]? || ""}",
        "HOME" => tmpdir,
        "XDG_CONFIG_HOME" => File.join(tmpdir, "xdg"),
      }

      stdout, stderr, status = run_cli(["@reviewer", "hello"], env)
      status.success?.should be_true
      stdout.should eq("roocode hello\n")
      stderr.should contain(%(warning: runner "roocode" does not support agents; ignoring @reviewer))
    ensure
      `rm -rf #{Process.quote(tmpdir)}` if Dir.exists?(tmpdir)
    end
  end
end

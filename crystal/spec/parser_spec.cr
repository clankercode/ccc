require "spec"
require "../src/call_coding_clis/parser"
require "../src/call_coding_clis/config"

describe "parse_args" do
  it "parses prompt-only input" do
    parsed = parse_args(["hello world"])
    parsed.runner.should be_nil
    parsed.thinking.should be_nil
    parsed.provider.should be_nil
    parsed.model.should be_nil
    parsed.alias.should be_nil
    parsed.prompt.should eq("hello world")
  end

  it "parses runner selector" do
    parsed = parse_args(["claude", "fix the bug"])
    parsed.runner.should eq("claude")
    parsed.prompt.should eq("fix the bug")
  end

  it "parses abbreviated runner selector" do
    parsed = parse_args(["cc", "test"])
    parsed.runner.should eq("cc")
  end

  it "parses codex and roocode selectors" do
    parse_args(["c", "test"]).runner.should eq("c")
    parse_args(["cx", "test"]).runner.should eq("cx")
    parse_args(["rc", "test"]).runner.should eq("rc")
  end

  it "parses case-insensitive runner selector" do
    parsed = parse_args(["Claude", "test"])
    parsed.runner.should eq("claude")
  end

  it "parses thinking level" do
    parsed = parse_args(["+3", "think hard"])
    parsed.thinking.should eq(3)
    parsed.prompt.should eq("think hard")
  end

  it "parses provider:model format" do
    parsed = parse_args([":anthropic:claude-sonnet-4", "hello"])
    parsed.provider.should eq("anthropic")
    parsed.model.should eq("claude-sonnet-4")
    parsed.prompt.should eq("hello")
  end

  it "parses model-only format" do
    parsed = parse_args([":gpt-4o", "hello"])
    parsed.model.should eq("gpt-4o")
    parsed.provider.should be_nil
  end

  it "parses alias" do
    parsed = parse_args(["@work", "do stuff"])
    parsed.alias.should eq("work")
    parsed.prompt.should eq("do stuff")
  end

  it "parses full combo" do
    parsed = parse_args(["claude", "+2", ":openai:gpt-4o", "@fast", "my prompt"])
    parsed.runner.should eq("claude")
    parsed.thinking.should eq(2)
    parsed.provider.should eq("openai")
    parsed.model.should eq("gpt-4o")
    parsed.alias.should eq("fast")
    parsed.prompt.should eq("my prompt")
  end

  it "joins multiple positional args as prompt" do
    parsed = parse_args(["fix", "the", "bug"])
    parsed.prompt.should eq("fix the bug")
  end

  it "treats runner-like token as positional after positional" do
    parsed = parse_args(["hello", "claude"])
    parsed.runner.should be_nil
    parsed.prompt.should eq("hello claude")
  end

  it "takes only first runner selector" do
    parsed = parse_args(["claude", "kimi", "test"])
    parsed.runner.should eq("claude")
    parsed.prompt.should eq("kimi test")
  end
end

describe "resolve_command" do
  it "resolves default runner (opencode)" do
    parsed = parse_args(["hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["opencode", "run", "hello"])
    env.should be_empty
  end

  it "resolves claude runner" do
    parsed = parse_args(["claude", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["claude", "hello"])
    env.should be_empty
  end

  it "resolves claude via cc abbreviation" do
    parsed = parse_args(["cc", "hello"])
    argv, env = resolve_command(parsed)
    argv[0].should eq("claude")
  end

  it "resolves codex via c and cx selectors" do
    ["c", "cx"].each do |selector|
      parsed = parse_args([selector, "hello"])
      argv, env = resolve_command(parsed)
      argv[0].should eq("codex")
      env.should be_empty
    end
  end

  it "resolves roocode via rc selector" do
    parsed = parse_args(["rc", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["roocode", "hello"])
    env.should be_empty
  end

  it "applies thinking flags for claude" do
    parsed = parse_args(["claude", "+2", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["claude", "--thinking", "medium", "hello"])
  end

  it "applies thinking=0 flags for claude" do
    parsed = parse_args(["claude", "+0", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["claude", "--no-thinking", "hello"])
  end

  it "applies model flag for claude" do
    parsed = parse_args(["claude", ":my-model", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["claude", "--model", "my-model", "hello"])
  end

  it "sets provider env var" do
    parsed = parse_args([":anthropic:some-model", "hello"])
    argv, env = resolve_command(parsed)
    env["CCC_PROVIDER"].should eq("anthropic")
  end

  it "raises on empty prompt" do
    parsed = parse_args([] of String)
    expect_raises(ArgumentError, /empty/) do
      resolve_command(parsed)
    end
  end

  it "raises on whitespace-only prompt" do
    parsed = parse_args(["   "])
    expect_raises(ArgumentError, /empty/) do
      resolve_command(parsed)
    end
  end

  it "uses config default runner" do
    parsed = parse_args(["hello"])
    config = CccConfig.new(default_runner: "claude")
    argv, env = resolve_command(parsed, config)
    argv[0].should eq("claude")
  end

  it "uses remapped config default runner" do
    parsed = parse_args(["hello"])
    config = CccConfig.new(default_runner: "c")
    argv, env = resolve_command(parsed, config)
    argv[0].should eq("codex")
  end

  it "uses config default thinking" do
    parsed = parse_args(["claude", "hello"])
    config = CccConfig.new(default_thinking: 3)
    argv, env = resolve_command(parsed, config)
    argv.should contain("--thinking")
    argv.should contain("high")
  end

  it "uses alias from config" do
    config = CccConfig.new
    config.aliases["work"] = AliasDef.new(runner: "claude", thinking: 2)
    parsed = parse_args(["@work", "hello"])
    argv, env = resolve_command(parsed, config)
    argv[0].should eq("claude")
    argv.should contain("--thinking")
    argv.should contain("medium")
  end

  it "uses preset agent from config" do
    config = CccConfig.new
    config.aliases["work"] = AliasDef.new(agent: "specialist")
    parsed = parse_args(["@work", "hello"])
    argv, env = resolve_command(parsed, config)
    argv.should eq(["opencode", "run", "--agent", "specialist", "hello"])
    env.should be_empty
  end

  it "falls back to agent when preset is missing" do
    parsed = parse_args(["@reviewer", "hello"])
    argv, env = resolve_command(parsed)
    argv.should eq(["opencode", "run", "--agent", "reviewer", "hello"])
    env.should be_empty
  end

  it "warns when runner does not support agents" do
    parsed = parse_args(["rc", "@reviewer", "hello"])
    warnings = [] of String
    argv, env = resolve_command(parsed, CccConfig.new, warnings)
    argv.should eq(["roocode", "hello"])
    env.should be_empty
    warnings.should eq([
      %(warning: runner "roocode" does not support agents; ignoring @reviewer),
    ])
  end

  it "resolves abbreviation from config" do
    config = CccConfig.new
    config.abbreviations["oc"] = "claude"
    parsed = parse_args(["oc", "hello"])
    argv, env = resolve_command(parsed, config)
    argv[0].should eq("claude")
  end
end

describe "load_config" do
  it "returns default config for missing file" do
    config = load_config("/nonexistent_path_12345/config")
    config.default_runner.should eq("oc")
    config.aliases.should be_empty
    config.abbreviations.should be_empty
  end

  it "parses a config file" do
    tmpdir = File.join(Dir.tempdir, "ccc_test_#{Random.rand(999999)}")
    Dir.mkdir_p(tmpdir)
    begin
      path = File.join(tmpdir, "config")
      File.write(path, <<-CFG)
        [defaults]
        runner = claude
        provider = openai
        model = gpt-4o
        thinking = 3

        [abbreviations]
        my = claude

        [aliases.work]
        runner = kimi
        thinking = 1
        agent = reviewer
        CFG
      config = load_config(path)
      config.default_runner.should eq("claude")
      config.default_provider.should eq("openai")
      config.default_model.should eq("gpt-4o")
      config.default_thinking.should eq(3)
      config.abbreviations["my"].should eq("claude")
      config.aliases["work"].runner.should eq("kimi")
      config.aliases["work"].thinking.should eq(1)
      config.aliases["work"].agent.should eq("reviewer")
    ensure
      `rm -rf #{Process.quote(tmpdir)}` if Dir.exists?(tmpdir)
    end
  end

  it "prefers XDG config over CCC_CONFIG" do
    tmpdir = File.join(Dir.tempdir, "ccc_test_env_#{Random.rand(999999)}")
    Dir.mkdir_p(tmpdir)
    begin
      legacy_path = File.join(tmpdir, "legacy-config")
      xdg_dir = File.join(tmpdir, "xdg")
      home_dir = File.join(tmpdir, "home")
      Dir.mkdir_p(File.join(xdg_dir, "ccc"))
      Dir.mkdir_p(File.join(home_dir, ".config", "ccc"))
      File.write(legacy_path, <<-CFG)
        [defaults]
        runner = codex
        CFG
      File.write(File.join(xdg_dir, "ccc", "config.toml"), <<-CFG)
        [defaults]
        runner = claude
        CFG

      old_ccc_config = ENV["CCC_CONFIG"]?
      old_xdg = ENV["XDG_CONFIG_HOME"]?
      old_home = ENV["HOME"]?

      begin
        ENV["CCC_CONFIG"] = legacy_path
        ENV["XDG_CONFIG_HOME"] = xdg_dir
        ENV["HOME"] = home_dir

        config = load_config
        config.default_runner.should eq("claude")
      ensure
        if old_ccc_config
          ENV["CCC_CONFIG"] = old_ccc_config
        else
          ENV.delete("CCC_CONFIG")
        end
        if old_xdg
          ENV["XDG_CONFIG_HOME"] = old_xdg
        else
          ENV.delete("XDG_CONFIG_HOME")
        end
        if old_home
          ENV["HOME"] = old_home
        else
          ENV.delete("HOME")
        end
      end
    ensure
      `rm -rf #{Process.quote(tmpdir)}` if Dir.exists?(tmpdir)
    end
  end
end

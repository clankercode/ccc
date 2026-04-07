defmodule CallCodingClis.ParserTest do
  use ExUnit.Case

  alias CallCodingClis.Parser
  alias CallCodingClis.Parser.{ParsedArgs, CccConfig, AliasDef}

  describe "parse_args/1" do
    test "prompt only" do
      parsed = Parser.parse_args(["hello world"])
      assert parsed.prompt == "hello world"
      assert parsed.runner == nil
      assert parsed.thinking == nil
      assert parsed.provider == nil
      assert parsed.model == nil
      assert parsed.alias == nil
    end

    test "runner selector cc" do
      parsed = Parser.parse_args(["cc", "fix bug"])
      assert parsed.runner == "cc"
      assert parsed.prompt == "fix bug"
    end

    test "runner selector opencode" do
      parsed = Parser.parse_args(["opencode", "hello"])
      assert parsed.runner == "opencode"
      assert parsed.prompt == "hello"
    end

    test "thinking level" do
      parsed = Parser.parse_args(["+2", "hello"])
      assert parsed.thinking == 2
      assert parsed.prompt == "hello"
    end

    test "provider and model" do
      parsed = Parser.parse_args([":anthropic:claude-4", "hello"])
      assert parsed.provider == "anthropic"
      assert parsed.model == "claude-4"
      assert parsed.prompt == "hello"
    end

    test "model only" do
      parsed = Parser.parse_args([":gpt-4o", "hello"])
      assert parsed.model == "gpt-4o"
      assert parsed.provider == nil
      assert parsed.prompt == "hello"
    end

    test "alias" do
      parsed = Parser.parse_args(["@work", "hello"])
      assert parsed.alias == "work"
      assert parsed.prompt == "hello"
    end

    test "full combo" do
      parsed = Parser.parse_args(["cc", "+3", ":anthropic:claude-4", "@fast", "fix tests"])
      assert parsed.runner == "cc"
      assert parsed.thinking == 3
      assert parsed.provider == "anthropic"
      assert parsed.model == "claude-4"
      assert parsed.alias == "fast"
      assert parsed.prompt == "fix tests"
    end

    test "runner case insensitive" do
      parsed = Parser.parse_args(["CC", "hello"])
      assert parsed.runner == "cc"
    end

    test "thinking zero" do
      parsed = Parser.parse_args(["+0", "hello"])
      assert parsed.thinking == 0
    end

    test "thinking out of range not matched" do
      parsed = Parser.parse_args(["+5", "hello"])
      assert parsed.thinking == nil
      assert parsed.prompt == "+5 hello"
    end

    test "tokens after prompt become part of prompt" do
      parsed = Parser.parse_args(["cc", "hello", "+2"])
      assert parsed.runner == "cc"
      assert parsed.prompt == "hello +2"
    end

    test "multi word prompt" do
      parsed = Parser.parse_args(["fix", "the", "bug"])
      assert parsed.prompt == "fix the bug"
    end
  end

  describe "resolve_command/2" do
    test "default runner is opencode" do
      parsed = %ParsedArgs{prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert List.first(argv) == "opencode"
      assert "run" in argv
      assert "hello" in argv
    end

    test "claude runner" do
      parsed = %ParsedArgs{runner: "cc", prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert List.first(argv) == "claude"
      refute "run" in argv
      assert "hello" in argv
    end

    test "thinking flags for claude" do
      parsed = %ParsedArgs{runner: "cc", thinking: 2, prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert "--thinking" in argv
      assert "medium" in argv
    end

    test "thinking zero for claude" do
      parsed = %ParsedArgs{runner: "cc", thinking: 0, prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert "--no-thinking" in argv
    end

    test "model flag for claude" do
      parsed = %ParsedArgs{runner: "cc", model: "claude-4", prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert "--model" in argv
      assert "claude-4" in argv
    end

    test "provider sets env" do
      parsed = %ParsedArgs{provider: "anthropic", prompt: "hello"}
      assert {:ok, {_argv, env}} = Parser.resolve_command(parsed)
      assert env["CCC_PROVIDER"] == "anthropic"
    end

    test "empty prompt returns error" do
      parsed = %ParsedArgs{prompt: "   "}
      assert {:error, "prompt must not be empty"} = Parser.resolve_command(parsed)
    end

    test "config default runner" do
      config = %CccConfig{default_runner: "cc"}
      parsed = %ParsedArgs{prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert List.first(argv) == "claude"
    end

    test "config default thinking" do
      config = %CccConfig{default_runner: "cc", default_thinking: 1}
      parsed = %ParsedArgs{prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert "--thinking" in argv
      assert "low" in argv
    end

    test "config default model" do
      config = %CccConfig{default_runner: "cc", default_model: "claude-3.5"}
      parsed = %ParsedArgs{prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert "--model" in argv
      assert "claude-3.5" in argv
    end

    test "config abbreviation" do
      config = %CccConfig{abbreviations: %{"mycc" => "cc"}}
      parsed = %ParsedArgs{runner: "mycc", prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert List.first(argv) == "claude"
    end

    test "alias provides defaults" do
      config = %CccConfig{
        aliases: %{"work" => %AliasDef{runner: "cc", thinking: 3, model: "claude-4"}}
      }

      parsed = %ParsedArgs{alias: "work", prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert List.first(argv) == "claude"
      assert "--thinking" in argv
      assert "high" in argv
      assert "--model" in argv
      assert "claude-4" in argv
    end

    test "explicit overrides alias" do
      config = %CccConfig{
        aliases: %{"work" => %AliasDef{runner: "cc", thinking: 3, model: "claude-4"}}
      }

      parsed = %ParsedArgs{runner: "k", alias: "work", thinking: 1, prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed, config)
      assert List.first(argv) == "kimi"
      assert "--think" in argv
      assert "low" in argv
    end

    test "kimi thinking flags" do
      parsed = %ParsedArgs{runner: "k", thinking: 4, prompt: "hello"}
      assert {:ok, {argv, _env}} = Parser.resolve_command(parsed)
      assert "--think" in argv
      assert "max" in argv
    end
  end

  describe "runner_registry/0" do
    test "all selectors registered" do
      registry = Parser.runner_registry()

      for sel <- [
            "oc",
            "cc",
            "c",
            "k",
            "rc",
            "cr",
            "codex",
            "claude",
            "opencode",
            "kimi",
            "crush"
          ] do
        assert Map.has_key?(registry, sel), "Missing selector: #{sel}"
      end
    end

    test "abbreviations point to same info" do
      registry = Parser.runner_registry()
      assert registry["oc"] == registry["opencode"]
      assert registry["cc"] == registry["claude"]
      assert registry["c"] == registry["claude"]
      assert registry["k"] == registry["kimi"]
    end
  end
end

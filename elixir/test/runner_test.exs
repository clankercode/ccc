defmodule CallCodingClis.RunnerTest do
  use ExUnit.Case

  alias CallCodingClis.{CommandSpec, PromptSpec, Runner}

  describe "build_prompt_spec/1" do
    test "builds spec with trimmed prompt" do
      spec = PromptSpec.build("hello")
      assert spec.argv == ["opencode", "run", "hello"]
    end

    test "trims whitespace from prompt" do
      spec = PromptSpec.build("  foo  ")
      assert spec.argv == ["opencode", "run", "foo"]
    end

    test "rejects empty prompt" do
      assert_raise ArgumentError, ~r/empty/, fn ->
        PromptSpec.build("")
      end
    end

    test "rejects whitespace-only prompt" do
      assert_raise ArgumentError, ~r/empty/, fn ->
        PromptSpec.build("   ")
      end
    end
  end

  describe "Runner.run/1" do
    test "captures stdout from subprocess" do
      spec = %CommandSpec{argv: ["echo", "hello"]}
      result = Runner.run(spec)
      assert result.exit_code == 0
      assert result.stdout == "hello\n"
    end

    test "captures stderr from subprocess" do
      spec = %CommandSpec{argv: ["sh", "-c", "echo err >&2"]}
      result = Runner.run(spec)
      assert result.exit_code == 0
      assert result.stderr == "err\n"
    end

    test "forwards non-zero exit code" do
      spec = %CommandSpec{argv: ["sh", "-c", "exit 42"]}
      result = Runner.run(spec)
      assert result.exit_code == 42
    end

    test "reports startup failure for nonexistent binary" do
      spec = %CommandSpec{argv: ["/nonexistent_binary_xyz"]}
      result = Runner.run(spec)
      assert result.exit_code == 1
      assert result.stdout == ""
      assert String.starts_with?(result.stderr, "failed to start /nonexistent_binary_xyz:")
    end

    test "supports stdin_text" do
      spec = %CommandSpec{argv: ["cat"], stdin_text: "input data"}
      result = Runner.run(spec)
      assert result.exit_code == 0
      assert result.stdout == "input data"
    end

    test "supports cwd" do
      spec = %CommandSpec{argv: ["pwd"], cwd: "/tmp"}
      result = Runner.run(spec)
      assert result.exit_code == 0
      assert String.trim(result.stdout) == "/tmp"
    end

    test "supports env overrides" do
      spec = %CommandSpec{
        argv: ["sh", "-c", "echo $CCC_TEST_VAR"],
        env: %{"CCC_TEST_VAR" => "hello_env"}
      }

      result = Runner.run(spec)
      assert result.exit_code == 0
      assert String.trim(result.stdout) == "hello_env"
    end
  end

  describe "Runner.stream/2" do
    test "invokes callback with stdout" do
      spec = %CommandSpec{argv: ["echo", "streamed"]}
      test_pid = self()

      result =
        Runner.stream(spec, fn type, data ->
          send(test_pid, {:event, type, data})
        end)

      assert result.exit_code == 0
      assert result.stdout == "streamed\n"

      receive do
        {:event, "stdout", data} -> assert data == "streamed\n"
      after
        1000 -> flunk("expected stdout callback event")
      end
    end

    test "invokes callback with stderr" do
      spec = %CommandSpec{argv: ["sh", "-c", "echo err >&2"]}
      test_pid = self()

      result =
        Runner.stream(spec, fn type, data ->
          send(test_pid, {:event, type, data})
        end)

      assert result.exit_code == 0
      assert result.stderr == "err\n"

      receive do
        {:event, "stderr", data} -> assert data == "err\n"
      after
        1000 -> flunk("expected stderr callback event")
      end
    end
  end
end

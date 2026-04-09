defmodule CallCodingClis.HelpTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias CallCodingClis.Help

  test "help text mentions name slot and agent fallback" do
    output = capture_io(fn -> Help.print_help() end)
    assert output =~ "[@name]"
    assert output =~ "if no preset exists, treat it as an agent"
  end

  test "usage mentions name slot" do
    output = capture_io(:stderr, fn -> Help.print_usage() end)
    assert output =~ "[@name]"
  end
end

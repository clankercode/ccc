defmodule CallCodingClis.Runner do
  alias CallCodingClis.{CommandSpec, CompletedRun}

  def run(%CommandSpec{} = spec) do
    [bin | args] = spec.argv

    case System.find_executable(bin) do
      nil ->
        startup_failure(spec, bin, "no such file or directory")

      resolved ->
        do_run(spec, resolved, args, bin)
    end
  end

  def stream(%CommandSpec{} = spec, on_event) when is_function(on_event, 2) do
    result = run(spec)

    if result.stdout != "", do: on_event.("stdout", result.stdout)
    if result.stderr != "", do: on_event.("stderr", result.stderr)

    result
  end

  defp do_run(spec, resolved, args, bin) do
    stderr_path = temp_path()
    {stdin_part, stdin_path} = build_stdin(spec.stdin_text)

    try do
      escaped_args =
        [resolved | args]
        |> Enum.map(&shell_escape/1)
        |> Enum.join(" ")

      env_part =
        if map_size(spec.env) == 0 do
          ""
        else
          spec.env
          |> Enum.map(fn {k, v} -> "#{shell_escape(k)}=#{shell_escape(v)}" end)
          |> Enum.join(" ")
          |> then(&(&1 <> " "))
        end

      shell_cmd =
        "#{env_part}#{stdin_part}#{escaped_args} 2>#{shell_escape(stderr_path)}"

      opts =
        [into: ""]
        |> maybe_put(:cd, spec.cwd)

      {stdout, exit_code} = System.cmd("sh", ["-c", shell_cmd], opts)

      %CompletedRun{
        argv: spec.argv,
        exit_code: exit_code,
        stdout: stdout,
        stderr: read_and_delete(stderr_path)
      }
    catch
      kind, reason ->
        startup_failure(spec, bin, format_err({kind, reason}))
    after
      File.rm(stderr_path)
      cleanup(stdin_path)
    end
  end

  defp build_stdin(nil), do: {"", nil}

  defp build_stdin(text) do
    path = temp_path()
    File.write!(path, text)
    {"cat #{shell_escape(path)} | ", path}
  end

  defp startup_failure(spec, bin, msg) do
    %CompletedRun{
      argv: spec.argv,
      exit_code: 1,
      stdout: "",
      stderr: "failed to start #{bin}: #{msg}\n"
    }
  end

  defp shell_escape(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end

  defp temp_path do
    Path.join(System.tmp_dir!(), "ccc_#{:erlang.unique_integer([:positive])}")
  end

  defp read_and_delete(path) do
    case File.read(path) do
      {:ok, data} ->
        File.rm(path)
        data

      _ ->
        ""
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp cleanup(nil), do: :ok

  defp cleanup(path) do
    File.rm(path)
  end

  defp format_err({:error, :enoent}), do: "no such file or directory"
  defp format_err({:error, :eacces}), do: "permission denied"
  defp format_err({:error, %ErlangError{original: o}}), do: inspect(o)
  defp format_err({kind, val}), do: "#{kind}: #{inspect(val)}"
  defp format_err(val), do: inspect(val)
end

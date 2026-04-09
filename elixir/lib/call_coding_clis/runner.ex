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
    {stdin_prefix, stdin_path} = build_stdin_prefix(spec.stdin_text)

    try do
      escaped = [resolved | args] |> Enum.map(&shell_escape/1) |> Enum.join(" ")

      stdin_redirect = if stdin_path, do: "", else: " </dev/null"

      shell_cmd =
        "#{stdin_prefix}#{escaped} 2>#{shell_escape(stderr_path)}#{stdin_redirect}"

      opts =
        [into: ""]
        |> maybe_put(:cd, spec.cwd)
        |> add_env_opt(spec.env)

      {stdout, exit_code} = System.cmd("sh", ["-c", shell_cmd], opts)

      stderr = read_and_delete(stderr_path)
      cleanup(stdin_path)

      %CompletedRun{
        argv: spec.argv,
        exit_code: exit_code,
        stdout: stdout,
        stderr: stderr
      }
    catch
      kind, reason ->
        cleanup(stdin_path)
        read_and_delete(stderr_path)
        startup_failure(spec, bin, format_err({kind, reason}))
    end
  end

  defp startup_failure(spec, bin, msg) do
    %CompletedRun{
      argv: spec.argv,
      exit_code: 1,
      stdout: "",
      stderr: "failed to start #{bin}: #{msg}\n"
    }
  end

  defp build_stdin_prefix(nil), do: {"", nil}

  defp build_stdin_prefix(text) do
    path = temp_path()
    File.write!(path, text)
    {"cat #{shell_escape(path)} | ", path}
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

  defp cleanup(nil), do: :ok

  defp cleanup(path) do
    File.rm(path)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp add_env_opt(opts, overrides) when map_size(overrides) == 0, do: opts

  defp add_env_opt(opts, overrides) do
    env_list = Enum.map(overrides, fn {k, v} -> {k, v} end)
    Keyword.put(opts, :env, env_list)
  end

  defp format_err({:error, :enoent}), do: "no such file or directory"
  defp format_err({:error, :eacces}), do: "permission denied"
  defp format_err({:error, %ErlangError{original: o}}), do: inspect(o)
  defp format_err({kind, val}), do: "#{kind}: #{inspect(val)}"
  defp format_err(val), do: inspect(val)
end

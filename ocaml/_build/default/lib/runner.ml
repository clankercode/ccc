type t = {
  executor : Command_spec.t -> Completed_run.t;
}

let build_env overrides =
  let current = Array.to_list (Unix.environment ()) in
  let overridden = List.fold_left (fun acc (k, v) ->
    let prefix = k ^ "=" in
    if List.exists (fun e -> String.starts_with ~prefix e) acc then
      List.map (fun e ->
        if String.starts_with ~prefix e then prefix ^ v else e
      ) acc
    else
      acc @ [prefix ^ v]
  ) current overrides in
  Array.of_list overridden

let set_cloexec fd = Unix.set_close_on_exec fd

let default_run spec =
  let argv = spec.Command_spec.argv in
  let argv0 = match argv with [] -> "(unknown)" | a :: _ -> a in
  let argv_arr = Array.of_list argv in
  let env_arr = build_env spec.Command_spec.env in
  let orig_cwd = ref None in
  try
    (match spec.Command_spec.cwd with
     | Some d ->
       orig_cwd := Some (Sys.getcwd ());
       Sys.chdir d
     | None -> ());
    let (stdout_r, stdout_w) = Unix.pipe () in
    let (stderr_r, stderr_w) = Unix.pipe () in
    let has_stdin = spec.Command_spec.stdin_text <> None in
    let stdin_r, stdin_w =
      if has_stdin then
        let (r, w) = Unix.pipe () in
        set_cloexec r;
        set_cloexec w;
        (r, w)
      else (Unix.stdin, Unix.stdin)
    in
    set_cloexec stdout_r;
    set_cloexec stdout_w;
    set_cloexec stderr_r;
    set_cloexec stderr_w;
    let pid =
      Unix.create_process_env
        argv0
        argv_arr
        env_arr
        (if has_stdin then stdin_r else Unix.stdin)
        stdout_w
        stderr_w
    in
    if has_stdin then Unix.close stdin_r;
    Unix.close stdout_w;
    Unix.close stderr_w;
    if has_stdin then begin
      let oc = Unix.out_channel_of_descr stdin_w in
      (match spec.Command_spec.stdin_text with
       | Some text -> output_string oc text
       | None -> ());
      close_out oc
    end;
    let read_all fd =
      let buf = Buffer.create 4096 in
      let tmp = Bytes.create 4096 in
      let rec loop () =
        match Unix.read fd tmp 0 4096 with
        | 0 -> ()
        | n -> Buffer.add_substring buf (Bytes.unsafe_to_string tmp) 0 n; loop ()
      in
      loop ();
      Buffer.contents buf
    in
    let stdout_data = read_all stdout_r in
    let stderr_data = read_all stderr_r in
    Unix.close stdout_r;
    Unix.close stderr_r;
    let _, status = Unix.waitpid [] pid in
    (match !orig_cwd with
     | Some d -> Sys.chdir d
     | None -> ());
    let exit_code = match status with
      | Unix.WEXITED n -> n
      | Unix.WSIGNALED _ -> 1
      | Unix.WSTOPPED _ -> 1
    in
    Completed_run.make ~argv ~exit_code ~stdout:stdout_data ~stderr:stderr_data
  with exn ->
    (match !orig_cwd with
     | Some d -> (try Sys.chdir d with _ -> ())
     | None -> ());
    Completed_run.make
      ~argv
      ~exit_code:1
      ~stdout:""
      ~stderr:(Error_format.startup_failure argv0 (Printexc.to_string exn))

let make ?(executor = default_run) () = { executor }

let run t spec = t.executor spec

let stream t spec on_event =
  let result = run t spec in
  if result.Completed_run.stdout <> "" then on_event "stdout" result.Completed_run.stdout;
  if result.Completed_run.stderr <> "" then on_event "stderr" result.Completed_run.stderr;
  result

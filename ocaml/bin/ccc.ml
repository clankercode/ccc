let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if args = [] then begin
    prerr_endline "usage: ccc [runner] [+thinking] [:provider:model] [@alias] <prompt>";
    exit 1
  end;
  try
    let parsed = Ccc_lib.Parser.parse_args args in
    let config = Ccc_lib.Config.load_config None in
    let argv, env = Ccc_lib.Parser.resolve_command parsed (Some config) in
    let spec = Ccc_lib.Command_spec.make ~env argv in
    let spec =
      match Sys.getenv "CCC_REAL_OPENCODE" with
      | real_bin ->
        { spec with Ccc_lib.Command_spec.argv =
            real_bin :: List.tl spec.Ccc_lib.Command_spec.argv }
      | exception Not_found -> spec
    in
    let runner = Ccc_lib.Runner.make () in
    let result = Ccc_lib.Runner.run runner spec in
    if result.Ccc_lib.Completed_run.stdout <> "" then
      output_string stdout result.Ccc_lib.Completed_run.stdout;
    if result.Ccc_lib.Completed_run.stderr <> "" then
      output_string stderr result.Ccc_lib.Completed_run.stderr;
    exit result.Ccc_lib.Completed_run.exit_code
  with Ccc_lib.Parser.Empty_prompt ->
    prerr_endline "prompt must not be empty";
    exit 1

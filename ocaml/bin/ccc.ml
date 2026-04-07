let () =
  let args = List.tl (Array.to_list Sys.argv) in
  match args with
  | [prompt] ->
    (try
      let spec = Ccc_lib.Prompt_spec.build_prompt_spec prompt in
      let spec =
        match Sys.getenv "CCC_REAL_OPENCODE" with
        | real_bin ->
          { spec with Ccc_lib.Command_spec.argv = real_bin :: List.tl spec.Ccc_lib.Command_spec.argv }
        | exception Not_found -> spec
      in
      let runner = Ccc_lib.Runner.make () in
      let result = Ccc_lib.Runner.run runner spec in
      if result.Ccc_lib.Completed_run.stdout <> "" then
        output_string stdout result.Ccc_lib.Completed_run.stdout;
      if result.Ccc_lib.Completed_run.stderr <> "" then
        output_string stderr result.Ccc_lib.Completed_run.stderr;
      exit result.Ccc_lib.Completed_run.exit_code
    with Ccc_lib.Prompt_spec.Empty_prompt ->
      prerr_endline "prompt must not be empty";
      exit 1)
  | _ ->
    prerr_endline "usage: ccc \"<Prompt>\"";
    exit 1

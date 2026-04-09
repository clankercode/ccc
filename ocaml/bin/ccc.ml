let runners = [| "opencode"; "claude"; "kimi"; "codex"; "crush" |]

let runner_checklist () =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "Runners:\n";
  Array.iter (fun name ->
    let found, ver =
      try
        let cmd = Printf.sprintf "which %s >/dev/null 2>&1 && %s --version 2>/dev/null" name name in
        let ic = Unix.open_process_in cmd in
        let v = try input_line ic with End_of_file -> "" in
        let _ = Unix.close_process_in ic in
        if v <> "" then (true, v) else (true, "found")
      with _ -> (false, "")
    in
    if found then
      Buffer.add_string buf (Printf.sprintf "  [+] %-10s (%s)  %s\n" name name ver)
    else
      Buffer.add_string buf (Printf.sprintf "  [-] %-10s (%s)  not found\n" name name)
  ) runners;
  Buffer.contents buf

let help_text = {|
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @alias        Use a named preset from config

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations

|}

let print_help () =
  print_string help_text;
  print_string (runner_checklist ());
  print_newline ()

let print_usage () =
  prerr_endline "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"";
  prerr_string (runner_checklist ());
  prerr_newline ()

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if args = ["--help"] || args = ["-h"] then begin
    print_help ();
    exit 0
  end;
  if args = [] then begin
    print_usage ();
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

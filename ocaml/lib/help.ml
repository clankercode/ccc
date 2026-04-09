let help_text = "\
ccc - call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc \"Fix the failing tests\"
  ccc oc \"Refactor auth module\"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 \"Add tests\"
  ccc k +4 \"Debug the parser\"
  ccc @reviewer \"Audit the API boundary\"
  ccc codex \"Write a unit test\"

Config:
  ~/.config/ccc/config.toml  - default runner, presets, abbreviations
"

let canonical_runners = [
  ("opencode", "oc");
  ("claude", "cc");
  ("kimi", "k");
  ("codex", "rc");
  ("crush", "cr");
]

let split_path_var () =
  try
    let v = Sys.getenv "PATH" in
    String.split_on_char ':' v
  with Not_found -> []

let which binary =
  let dirs = split_path_var () in
  let rec search = function
    | [] -> None
    | d :: rest ->
      let candidate = d ^ "/" ^ binary in
      if Sys.file_exists candidate && Unix.access candidate [Unix.X_OK] = ()
      then Some candidate
      else search rest
  in
  search dirs

let get_version binary =
  try
    let argv = [| binary; "--version" |] in
    let (stdout_r, stdout_w) = Unix.pipe () in
    let null_r = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    let pid = Unix.create_process binary argv null_r stdout_w Unix.stderr in
    Unix.close stdout_w;
    Unix.close null_r;
    let timeout = 3.0 in
    let start = Unix.gettimeofday () in
    let buf = Buffer.create 256 in
    let tmp = Bytes.create 256 in
    let finished = ref false in
    (try while true do
       let elapsed = Unix.gettimeofday () -. start in
       if elapsed > timeout then raise Exit;
       let ready, _, _ = Unix.select [stdout_r] [] [] 0.1 in
       if List.mem stdout_r ready then
         match Unix.read stdout_r tmp 0 256 with
         | 0 -> raise Exit
         | n -> Buffer.add_subbytes buf tmp 0 n
     done with Exit -> ());
    Unix.close stdout_r;
    if !finished then ()
    else (
      let (waited_pid, _) = Unix.waitpid [Unix.WNOHANG] pid in
      if waited_pid = 0 then (
        Unix.kill pid Sys.sigkill;
        ignore (Unix.waitpid [] pid)
      )
    );
    let s = Buffer.contents buf in
    let trimmed = String.trim s in
    if trimmed = "" then "" else
      match String.index_opt trimmed '\n' with
      | Some i -> String.sub trimmed 0 i
      | None -> trimmed
  with _ -> ""

let runner_checklist () =
  let lines = Buffer.create 256 in
  Buffer.add_string lines "Runners:\n";
  List.iter (fun (name, _) ->
    let binary = match Hashtbl.find_opt Parser.runner_registry name with
      | Some info -> info.binary
      | None -> name
    in
    match which binary with
    | Some _ ->
      let version = get_version binary in
      let tag = if version <> "" then version else "found" in
      Buffer.add_string lines
        (Printf.sprintf "  [+] %-10s (%s)  %s\n" name binary tag)
    | None ->
      Buffer.add_string lines
        (Printf.sprintf "  [-] %-10s (%s)  not found\n" name binary)
  ) canonical_runners;
  Buffer.contents lines

let print_help () =
  output_string stdout help_text;
  output_string stdout "\n";
  output_string stdout (runner_checklist ())

let print_usage () =
  output_string stderr "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"\n";
  output_string stderr (runner_checklist ())

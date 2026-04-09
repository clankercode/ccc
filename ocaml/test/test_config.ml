let rec mkdir_p path =
  if path = "" || path = "." || path = "/" || Sys.file_exists path then
    ()
  else begin
    mkdir_p (Filename.dirname path);
    if not (Sys.file_exists path) then Unix.mkdir path 0o700
  end

let write_file path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

let find_alias name aliases =
  match List.assoc_opt name aliases with
  | Some alias -> alias
  | None -> failwith ("missing alias: " ^ name)

let () =
  let open Alcotest in
  let open Ccc_lib in
  run "config" [
    ("load_config", [
      test_case "ignores empty CCC_CONFIG and loads xdg preset agent" `Quick (fun () ->
        let suffix = string_of_int (int_of_float (Unix.gettimeofday () *. 1_000_000.)) in
        let base = Filename.concat (Filename.get_temp_dir_name ())
          ("ccc-config-" ^ string_of_int (Unix.getpid ()) ^ "-" ^ suffix)
        in
        mkdir_p base;
        let ccc_config = Filename.concat base "empty-config.toml" in
        write_file ccc_config "";
        let xdg_root = Filename.concat base "xdg" in
        let xdg_dir = Filename.concat xdg_root "ccc" in
        mkdir_p xdg_dir;
        write_file (Filename.concat xdg_dir "config.toml")
          "[defaults]\n\
           runner = \"claude\"\n\
           provider = \"anthropic\"\n\
           model = \"sonnet-4\"\n\
           thinking = 2\n\
           \n\
           [aliases.reviewer]\n\
           runner = \"opencode\"\n\
           thinking = 3\n\
           provider = \"anthropic\"\n\
           model = \"sonnet-4\"\n\
           agent = \"specialist\"\n\
           \n\
           [abbreviations]\n\
           c = \"codex\"\n";
        let home_root = Filename.concat base "home" in
        let home_dir = Filename.concat home_root ".config/ccc" in
        mkdir_p home_dir;
        write_file (Filename.concat home_dir "config.toml")
          "[defaults]\nrunner = \"codex\"\n";
        Unix.putenv "CCC_CONFIG" ccc_config;
        Unix.putenv "XDG_CONFIG_HOME" xdg_root;
        Unix.putenv "HOME" home_root;
        let config = Config.load_config None in
        check string "default runner" "claude" config.Parser.default_runner;
        check string "default provider" "anthropic" config.Parser.default_provider;
        check string "default model" "sonnet-4" config.Parser.default_model;
        check (option int) "default thinking" (Some 2) config.Parser.default_thinking;
        let reviewer = find_alias "reviewer" config.Parser.aliases in
        check (option string) "preset runner" (Some "opencode") reviewer.Parser.ad_runner;
        check (option int) "preset thinking" (Some 3) reviewer.Parser.ad_thinking;
        check (option string) "preset provider" (Some "anthropic") reviewer.Parser.ad_provider;
        check (option string) "preset model" (Some "sonnet-4") reviewer.Parser.ad_model;
        check (option string) "preset agent" (Some "specialist") reviewer.Parser.ad_agent;
        check (list (pair string string)) "abbreviations" [("c", "codex")] config.Parser.abbreviations);

      test_case "legacy alias syntax can set agent" `Quick (fun () ->
        let suffix = string_of_int (int_of_float (Unix.gettimeofday () *. 1_000_000.)) in
        let base = Filename.concat (Filename.get_temp_dir_name ())
          ("ccc-config-legacy-" ^ string_of_int (Unix.getpid ()) ^ "-" ^ suffix)
        in
        mkdir_p base;
        let legacy_path = Filename.concat base "config" in
        write_file legacy_path
          "default_runner = claude\n\
           alias = reviewer runner=opencode thinking=3 provider=anthropic model=sonnet-4 agent=review-bot\n\
           abbrev = c codex\n";
        let config = Config.load_config (Some legacy_path) in
        check string "default runner" "claude" config.Parser.default_runner;
        let reviewer = find_alias "reviewer" config.Parser.aliases in
        check (option string) "preset runner" (Some "opencode") reviewer.Parser.ad_runner;
        check (option int) "preset thinking" (Some 3) reviewer.Parser.ad_thinking;
        check (option string) "preset provider" (Some "anthropic") reviewer.Parser.ad_provider;
        check (option string) "preset model" (Some "sonnet-4") reviewer.Parser.ad_model;
        check (option string) "preset agent" (Some "review-bot") reviewer.Parser.ad_agent;
        check (list (pair string string)) "abbreviations" [("c", "codex")] config.Parser.abbreviations);
    ]);
  ]

let () =
  let open Alcotest in
  let open Ccc_lib in
  let pa ~runner ~thinking ~provider ~model ~alias ~prompt =
      { Parser.runner; Parser.thinking; Parser.provider;
        Parser.model; Parser.alias; Parser.prompt }
  in
  run "parser" [
    ("parse_args", [
      test_case "prompt only" `Quick (fun () ->
        let r = Parser.parse_args ["hello"] in
        check (option string) "runner" None r.Parser.runner;
        check (option int) "thinking" None r.Parser.thinking;
        check (option string) "provider" None r.Parser.provider;
        check (option string) "model" None r.Parser.model;
        check (option string) "alias" None r.Parser.alias;
        check string "prompt" "hello" r.Parser.prompt);

      test_case "multi-word prompt" `Quick (fun () ->
        let r = Parser.parse_args ["hello"; "world"] in
        check string "prompt" "hello world" r.Parser.prompt;
        check (option string) "runner" None r.Parser.runner);

      test_case "runner selector" `Quick (fun () ->
        let r = Parser.parse_args ["cc"; "test"] in
        check (option string) "runner" (Some "cc") r.Parser.runner;
        check string "prompt" "test" r.Parser.prompt);

      test_case "runner selector case insensitive" `Quick (fun () ->
        let r = Parser.parse_args ["CC"; "test"] in
        check (option string) "runner" (Some "cc") r.Parser.runner);

      test_case "thinking" `Quick (fun () ->
        let r = Parser.parse_args ["+2"; "test"] in
        check (option int) "thinking" (Some 2) r.Parser.thinking;
        check string "prompt" "test" r.Parser.prompt);

      test_case "provider:model" `Quick (fun () ->
        let r = Parser.parse_args [":anthropic:sonnet-4"; "test"] in
        check (option string) "provider" (Some "anthropic") r.Parser.provider;
        check (option string) "model" (Some "sonnet-4") r.Parser.model;
        check string "prompt" "test" r.Parser.prompt);

      test_case "model only" `Quick (fun () ->
        let r = Parser.parse_args [":sonnet-4"; "test"] in
        check (option string) "model" (Some "sonnet-4") r.Parser.model;
        check (option string) "provider" None r.Parser.provider);

      test_case "alias" `Quick (fun () ->
        let r = Parser.parse_args ["@review"; "test"] in
        check (option string) "alias" (Some "review") r.Parser.alias;
        check string "prompt" "test" r.Parser.prompt);

      test_case "full combo" `Quick (fun () ->
        let r = Parser.parse_args
          ["claude"; "+3"; ":anthropic:sonnet-4"; "@review"; "fix"; "bugs"] in
        check (option string) "runner" (Some "claude") r.Parser.runner;
        check (option int) "thinking" (Some 3) r.Parser.thinking;
        check (option string) "provider" (Some "anthropic") r.Parser.provider;
        check (option string) "model" (Some "sonnet-4") r.Parser.model;
        check (option string) "alias" (Some "review") r.Parser.alias;
        check string "prompt" "fix bugs" r.Parser.prompt);

      test_case "positional swallows flags" `Quick (fun () ->
        let r = Parser.parse_args ["hello"; "+2"] in
        check string "prompt" "hello +2" r.Parser.prompt;
        check (option int) "thinking" None r.Parser.thinking);

      test_case "empty argv" `Quick (fun () ->
        let r = Parser.parse_args [] in
        check string "prompt" "" r.Parser.prompt);

      test_case "second runner becomes positional" `Quick (fun () ->
        let r = Parser.parse_args ["claude"; "oc"; "test"] in
        check (option string) "runner" (Some "claude") r.Parser.runner;
        check string "prompt" "oc test" r.Parser.prompt);

      test_case "abbrev runner oc" `Quick (fun () ->
        let r = Parser.parse_args ["oc"; "test"] in
        check (option string) "runner" (Some "oc") r.Parser.runner);
    ]);

    ("resolve_command", [
      test_case "default runner opencode" `Quick (fun () ->
        let parsed = Parser.parse_args ["hello"] in
        let argv, env = Parser.resolve_command parsed None in
        check (list string) "argv" ["opencode"; "run"; "hello"] argv;
        check (list (pair string string)) "env" [] env);

      test_case "claude runner" `Quick (fun () ->
        let parsed = Parser.parse_args ["claude"; "hello"] in
        let argv, env = Parser.resolve_command parsed None in
        check (list string) "argv" ["claude"; "hello"] argv;
        check (list (pair string string)) "env" [] env);

      test_case "claude thinking +3" `Quick (fun () ->
        let parsed = Parser.parse_args ["claude"; "+3"; "hello"] in
        let argv, env = Parser.resolve_command parsed None in
        check (list string) "argv"
          ["claude"; "--thinking"; "high"; "hello"] argv;
        check (list (pair string string)) "env" [] env);

      test_case "claude thinking 0 (no-thinking)" `Quick (fun () ->
        let parsed = Parser.parse_args ["claude"; "+0"; "hello"] in
        let argv, _ = Parser.resolve_command parsed None in
        check (list string) "argv" ["claude"; "--no-thinking"; "hello"] argv);

      test_case "codex model flag" `Quick (fun () ->
        let parsed = Parser.parse_args ["codex"; ":gpt-4"; "hello"] in
        let argv, _ = Parser.resolve_command parsed None in
        check (list string) "argv" ["codex"; "--model"; "gpt-4"; "hello"] argv);

      test_case "provider env override" `Quick (fun () ->
        let parsed = Parser.parse_args [":anthropic:sonnet-4"; "hello"] in
        let argv, env = Parser.resolve_command parsed None in
        check (list string) "argv" ["opencode"; "run"; "hello"] argv;
        check (list (pair string string)) "env"
          [("CCC_PROVIDER", "anthropic")] env);

      test_case "empty prompt raises" `Quick (fun () ->
        check_raises "empty" Parser.Empty_prompt (fun () ->
          let parsed = pa ~runner:None ~thinking:None ~provider:None
            ~model:None ~alias:None ~prompt:"" in
          ignore (Parser.resolve_command parsed None)));

      test_case "whitespace prompt raises" `Quick (fun () ->
        check_raises "ws" Parser.Empty_prompt (fun () ->
          let parsed = pa ~runner:None ~thinking:None ~provider:None
            ~model:None ~alias:None ~prompt:"   " in
          ignore (Parser.resolve_command parsed None)));

      test_case "alias with config" `Quick (fun () ->
        let parsed = Parser.parse_args ["@review"; "fix"; "bugs"] in
        let config = {
          Parser.default_runner = "oc"; Parser.default_provider = "";
          Parser.default_model = ""; Parser.default_thinking = None;
          Parser.aliases = [
            ("review", {
              Parser.ad_runner = Some "claude";
              Parser.ad_thinking = Some 3;
              Parser.ad_provider = None;
              Parser.ad_model = None;
            })
          ];
          Parser.abbreviations = [];
        } in
        let argv, env = Parser.resolve_command parsed (Some config) in
        check (list string) "argv"
          ["claude"; "--thinking"; "high"; "fix bugs"] argv;
        check (list (pair string string)) "env" [] env);

      test_case "kimi thinking +2" `Quick (fun () ->
        let parsed = Parser.parse_args ["kimi"; "+2"; "test"] in
        let argv, _ = Parser.resolve_command parsed None in
        check (list string) "argv"
          ["kimi"; "--think"; "medium"; "test"] argv);

      test_case "crush ignores model flag" `Quick (fun () ->
        let parsed = Parser.parse_args ["crush"; ":model-1"; "hello"] in
        let argv, _ = Parser.resolve_command parsed None in
        check (list string) "argv" ["crush"; "hello"] argv);

      test_case "config defaults" `Quick (fun () ->
        let parsed = Parser.parse_args ["hello"] in
        let config = {
          Parser.default_runner = "claude";
          Parser.default_provider = "anthropic";
          Parser.default_model = "sonnet-4";
          Parser.default_thinking = Some 2;
          Parser.aliases = [];
          Parser.abbreviations = [];
        } in
        let argv, env = Parser.resolve_command parsed (Some config) in
        check (list string) "argv"
          ["claude"; "--thinking"; "medium";
           "--model"; "sonnet-4"; "hello"] argv;
        check (list (pair string string)) "env"
          [("CCC_PROVIDER", "anthropic")] env);

      test_case "abbrev remaps runner name" `Quick (fun () ->
        let parsed = Parser.parse_args ["c"; "hello"] in
        let config = {
          Parser.default_runner = "oc"; Parser.default_provider = "";
          Parser.default_model = ""; Parser.default_thinking = None;
          Parser.aliases = [];
          Parser.abbreviations = [("c", "codex")];
        } in
        let argv, _ = Parser.resolve_command parsed (Some config) in
        check (list string) "argv" ["codex"; "hello"] argv
      );

      test_case "abbrev to claude with thinking" `Quick (fun () ->
        let parsed = Parser.parse_args ["rc"; "+1"; "hello"] in
        let config = {
          Parser.default_runner = "oc"; Parser.default_provider = "";
          Parser.default_model = ""; Parser.default_thinking = None;
          Parser.aliases = [];
          Parser.abbreviations = [("rc", "claude")];
        } in
        let argv, _ = Parser.resolve_command parsed (Some config) in
        check (list string) "argv"
          ["claude"; "--thinking"; "low"; "hello"] argv);

      test_case "opencode thinking ignored (no flags)" `Quick (fun () ->
        let parsed = Parser.parse_args ["oc"; "+2"; "hello"] in
        let argv, _ = Parser.resolve_command parsed None in
        check (list string) "argv" ["opencode"; "run"; "hello"] argv);
    ]);
  ]

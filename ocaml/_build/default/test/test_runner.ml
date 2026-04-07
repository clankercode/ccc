let contains_sub ~sub s =
  let sub_len = String.length sub in
  let s_len = String.length s in
  if sub_len = 0 then true
  else if sub_len > s_len then false
  else
    let max_start = s_len - sub_len in
    let rec loop i =
      if i > max_start then false
      else if String.sub s i sub_len = sub then true
      else loop (i + 1)
    in
    loop 0

let () =
  let open Alcotest in
  let open Ccc_lib in
  run "ccc_lib" [
    ("prompt_spec", [
      test_case "valid prompt" `Quick (fun () ->
        let spec = Prompt_spec.build_prompt_spec "hello" in
        check (list string) "argv" ["opencode"; "run"; "hello"] spec.Command_spec.argv);

      test_case "empty prompt raises" `Quick (fun () ->
        check_raises "empty" Prompt_spec.Empty_prompt (fun () ->
          ignore (Prompt_spec.build_prompt_spec "")));

      test_case "whitespace-only prompt raises" `Quick (fun () ->
        check_raises "ws" Prompt_spec.Empty_prompt (fun () ->
          ignore (Prompt_spec.build_prompt_spec "   ")));

      test_case "whitespace trimmed" `Quick (fun () ->
        let spec = Prompt_spec.build_prompt_spec "  foo  " in
        check (list string) "argv" ["opencode"; "run"; "foo"] spec.Command_spec.argv);
    ]);

    ("runner_mock", [
      test_case "mock executor" `Quick (fun () ->
        let mock spec =
          Completed_run.make
            ~argv:spec.Command_spec.argv
            ~exit_code:0
            ~stdout:"hello\n"
            ~stderr:""
        in
        let runner = Runner.make ~executor:mock () in
        let spec = Prompt_spec.build_prompt_spec "test" in
        let result = Runner.run runner spec in
        check int "exit_code" 0 result.Completed_run.exit_code;
        check string "stdout" "hello\n" result.Completed_run.stdout;
        check string "stderr" "" result.Completed_run.stderr);

      test_case "mock stream" `Quick (fun () ->
        let mock spec =
          Completed_run.make
            ~argv:spec.Command_spec.argv
            ~exit_code:0
            ~stdout:"out"
            ~stderr:"err"
        in
        let events = ref [] in
        let on_event kind data = events := (kind, data) :: !events in
        let runner = Runner.make ~executor:mock () in
        let spec = Prompt_spec.build_prompt_spec "test" in
        let result = Runner.stream runner spec on_event in
        check int "exit_code" 0 result.Completed_run.exit_code;
        let ev = List.rev !events in
        check int "event count" 2 (List.length ev);
        check (pair string string) "stdout event" ("stdout", "out") (List.nth ev 0);
        check (pair string string) "stderr event" ("stderr", "err") (List.nth ev 1));
    ]);

    ("error_format", [
      test_case "startup failure format" `Quick (fun () ->
        let msg = Error_format.startup_failure "mybin" "not found" in
        check bool "contains argv0" true (contains_sub ~sub:"mybin" msg);
        check bool "contains prefix" true (contains_sub ~sub:"failed to start" msg));
    ]);

    ("runner_real", [
      test_case "nonexistent binary startup failure" `Quick (fun () ->
        let spec = Command_spec.make ["/nonexistent_binary_xyz"] in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 1 result.Completed_run.exit_code;
        check bool "stderr prefix" true
          (String.starts_with
             ~prefix:"failed to start /nonexistent_binary_xyz"
             result.Completed_run.stderr));

      test_case "echo command" `Quick (fun () ->
        let spec = Command_spec.make ["/bin/sh"; "-c"; "echo hello"] in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 0 result.Completed_run.exit_code;
        check string "stdout" "hello\n" result.Completed_run.stdout);

      test_case "stderr capture" `Quick (fun () ->
        let spec = Command_spec.make ["/bin/sh"; "-c"; "echo err >&2"] in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 0 result.Completed_run.exit_code;
        check string "stderr" "err\n" result.Completed_run.stderr);

      test_case "nonzero exit code" `Quick (fun () ->
        let spec = Command_spec.make ["/bin/sh"; "-c"; "exit 42"] in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 42 result.Completed_run.exit_code);

      test_case "stdin_text" `Quick (fun () ->
        let spec = Command_spec.make
          ~stdin_text:(Some "hello from stdin\n")
          ["/bin/sh"; "-c"; "cat"]
        in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 0 result.Completed_run.exit_code;
        check string "stdout" "hello from stdin\n" result.Completed_run.stdout);

      test_case "env override" `Quick (fun () ->
        let spec = Command_spec.make
          ~env:[("CCC_TEST_VAR", "overridden")]
          ["/bin/sh"; "-c"; "echo $CCC_TEST_VAR"]
        in
        let runner = Runner.make () in
        let result = Runner.run runner spec in
        check int "exit_code" 0 result.Completed_run.exit_code;
        check string "stdout" "overridden\n" result.Completed_run.stdout);
    ]);
  ]

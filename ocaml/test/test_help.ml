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

let capture_channel out_channel f =
  let path = Filename.temp_file "ccc-help" ".txt" in
  let fd = Unix.descr_of_out_channel out_channel in
  let saved = Unix.dup fd in
  let capture_fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  flush out_channel;
  Unix.dup2 capture_fd fd;
  Unix.close capture_fd;
  Fun.protect
    ~finally:(fun () ->
      flush out_channel;
      Unix.dup2 saved fd;
      Unix.close saved)
    f;
  flush out_channel;
  let ic = open_in path in
  let len = in_channel_length ic in
  let contents = really_input_string ic len in
  close_in ic;
  Sys.remove path;
  contents

let () =
  let open Alcotest in
  let open Ccc_lib in
  run "help" [
    ("help_text", [
      test_case "help text mentions name fallback" `Quick (fun () ->
        check bool "contains [@name]" true
          (contains_sub ~sub:"[@name]" Help.help_text);
        check bool "contains preset fallback explanation" true
          (contains_sub
             ~sub:"Use a named preset from config; if no preset exists, treat it as an agent"
             Help.help_text));
    ]);

    ("print_help", [
      test_case "stdout mentions name fallback" `Quick (fun () ->
        Unix.putenv "PATH" "";
        let output = capture_channel stdout (fun () -> Help.print_help ()) in
        check bool "contains [@name]" true (contains_sub ~sub:"[@name]" output);
        check bool "contains fallback explanation" true
          (contains_sub
             ~sub:"Use a named preset from config; if no preset exists, treat it as an agent"
             output));
    ]);

    ("print_usage", [
      test_case "stderr uses name slot" `Quick (fun () ->
        Unix.putenv "PATH" "";
        let output = capture_channel stderr (fun () -> Help.print_usage ()) in
        check bool "contains usage line" true
          (contains_sub
             ~sub:"usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""
             output));
    ]);
  ]

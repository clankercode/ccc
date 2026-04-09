let split_words s =
  String.split_on_char ' ' s
  |> List.filter (fun w -> w <> "")

let parse_alias_fields fields =
  let runner = ref None in
  let thinking = ref None in
  let provider = ref None in
  let model = ref None in
  let agent = ref None in
  List.iter (fun field ->
    if String.starts_with ~prefix:"runner=" field then
      runner := Some (String.sub field 7 (String.length field - 7))
    else if String.starts_with ~prefix:"thinking=" field then
      (try thinking := Some (int_of_string (String.sub field 9 (String.length field - 9)))
       with Failure _ -> ())
    else if String.starts_with ~prefix:"provider=" field then
      provider := Some (String.sub field 9 (String.length field - 9))
    else if String.starts_with ~prefix:"model=" field then
      model := Some (String.sub field 6 (String.length field - 6))
    else if String.starts_with ~prefix:"agent=" field then
      agent := Some (String.sub field 6 (String.length field - 6))
  ) fields;
  { Parser.ad_runner = !runner; ad_thinking = !thinking;
    ad_provider = !provider; ad_model = !model; ad_agent = !agent }

let strip_quotes s =
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n-1] = '"'
  then String.sub s 1 (n - 2)
  else s

let load_config path_opt =
  let file_is_nonempty path =
    try
      let stat = Unix.stat path in
      stat.Unix.st_kind = Unix.S_REG && stat.Unix.st_size > 0
    with _ -> false
  in
  let search_paths () =
    match path_opt with
    | Some p -> [p]
    | None ->
      let paths = ref [] in
      (try
        let ccc = Sys.getenv "CCC_CONFIG" in
        if ccc <> "" && file_is_nonempty ccc then paths := ccc :: !paths
      with Not_found -> ());
      (try
        let xdg = Sys.getenv "XDG_CONFIG_HOME" in
        paths := !paths @ [xdg ^ "/ccc/config.toml"]
      with Not_found -> ());
      (try
        let home = Sys.getenv "HOME" in
        paths := !paths @ [home ^ "/.config/ccc/config.toml"]
      with Not_found -> ());
      !paths
  in
  let found_path = ref "" in
  List.iter (fun p ->
    if !found_path = "" && Sys.file_exists p then found_path := p
  ) (search_paths ());
  if !found_path = "" then
    { Parser.default_runner = "oc"; Parser.default_provider = "";
      Parser.default_model = ""; Parser.default_thinking = None;
      Parser.aliases = []; Parser.abbreviations = [] }
  else begin
    let ic = open_in !found_path in
    let runner = ref "oc" in
    let provider = ref "" in
    let model = ref "" in
    let thinking = ref None in
    let aliases = ref [] in
    let abbrevs = ref [] in
    let section = ref "" in
    let alias_name = ref "" in
    let alias_runner = ref None in
    let alias_thinking = ref None in
    let alias_provider = ref None in
    let alias_model = ref None in
    let alias_agent = ref None in
    let flush_alias () =
      if !alias_name <> "" then begin
        aliases := (!alias_name, { Parser.ad_runner = !alias_runner;
          Parser.ad_thinking = !alias_thinking; Parser.ad_provider = !alias_provider;
          Parser.ad_model = !alias_model; Parser.ad_agent = !alias_agent }) :: !aliases;
        alias_name := ""; alias_runner := None; alias_thinking := None;
        alias_provider := None; alias_model := None; alias_agent := None
      end in
    (try while true do
      let line = String.trim (input_line ic) in
      if line <> "" && String.length line > 0 && line.[0] <> '#' then begin
        if String.starts_with ~prefix:"[" line && String.ends_with ~suffix:"]" line then begin
          flush_alias ();
          let sec = String.sub line 1 (String.length line - 2) in
          section := sec
        end else if String.contains line '=' then begin
          let eq = String.index line '=' in
          let key = String.trim (String.sub line 0 eq) in
          let raw_val = String.trim (String.sub line (eq + 1) (String.length line - eq - 1)) in
          let val_ = strip_quotes raw_val in
          if !section = "defaults" then begin
            match key with
            | "runner" -> runner := val_
            | "provider" -> provider := val_
            | "model" -> model := val_
            | "thinking" ->
              (try thinking := Some (int_of_string val_) with Failure _ -> ())
            | _ -> ()
          end else if !section = "abbreviations" then begin
            abbrevs := (key, val_) :: !abbrevs
          end else if String.starts_with ~prefix:"aliases." !section then begin
            let aname = String.sub !section 8 (String.length !section - 8) in
            if !alias_name <> "" && !alias_name <> aname then flush_alias ();
            alias_name := aname;
            match key with
            | "runner" -> alias_runner := (if val_ = "" then None else Some val_)
            | "thinking" ->
              (try alias_thinking := Some (int_of_string val_) with Failure _ -> ())
            | "provider" -> alias_provider := (if val_ = "" then None else Some val_)
            | "model" -> alias_model := (if val_ = "" then None else Some val_)
            | "agent" -> alias_agent := (if val_ = "" then None else Some val_)
            | _ -> ()
          end else begin
            match key with
            | "default_runner" -> runner := val_
            | "default_provider" -> provider := val_
            | "default_model" -> model := val_
            | "default_thinking" ->
              (try thinking := Some (int_of_string val_) with Failure _ -> ())
            | "alias" ->
              (match split_words val_ with
               | name :: fields ->
                 aliases := (name, parse_alias_fields fields) :: !aliases
               | _ -> ())
            | "abbrev" ->
              (match split_words val_ with
               | short :: long :: _ -> abbrevs := (short, long) :: !abbrevs
               | _ -> ())
            | _ -> ()
          end
        end
      end
    done with End_of_file -> ());
    flush_alias ();
    close_in ic;
    { Parser.default_runner = !runner; Parser.default_provider = !provider;
      Parser.default_model = !model; Parser.default_thinking = !thinking;
      Parser.aliases = List.rev !aliases; Parser.abbreviations = List.rev !abbrevs }
  end

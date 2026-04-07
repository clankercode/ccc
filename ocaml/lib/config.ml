let split_words s =
  String.split_on_char ' ' s
  |> List.filter (fun w -> w <> "")

let parse_alias_fields fields =
  let runner = ref None in
  let thinking = ref None in
  let provider = ref None in
  let model = ref None in
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
  ) fields;
  { Parser.ad_runner = !runner; ad_thinking = !thinking;
    ad_provider = !provider; ad_model = !model }

let load_config path_opt =
  let path = match path_opt with
    | Some p -> p
    | None ->
      match Sys.getenv "CCC_CONFIG" with
      | p -> p
      | exception Not_found ->
        let home = (try Sys.getenv "HOME" with Not_found -> "") in
        home ^ "/.config/ccc/config"
  in
  if path = "" || not (Sys.file_exists path) then
    { Parser.default_runner = "oc"; Parser.default_provider = "";
      Parser.default_model = ""; Parser.default_thinking = None;
      Parser.aliases = []; Parser.abbreviations = [] }
  else begin
    let ic = open_in path in
    let runner = ref "oc" in
    let provider = ref "" in
    let model = ref "" in
    let thinking = ref None in
    let aliases = ref [] in
    let abbrevs = ref [] in
    (try while true do
      let line = String.trim (input_line ic) in
      if line <> "" && (String.length line = 0 || line.[0] <> '#') then
        match split_words line with
        | "default_runner" :: v :: _ -> runner := v
        | "default_provider" :: v :: _ -> provider := v
        | "default_model" :: v :: _ -> model := v
        | "default_thinking" :: v :: _ ->
          (try thinking := Some (int_of_string v) with Failure _ -> ())
        | "alias" :: name :: fields ->
          aliases := (name, parse_alias_fields fields) :: !aliases
        | "abbrev" :: short :: long :: _ ->
          abbrevs := (short, long) :: !abbrevs
        | _ -> ()
    done with End_of_file -> ());
    close_in ic;
    { Parser.default_runner = !runner; Parser.default_provider = !provider;
      Parser.default_model = !model; Parser.default_thinking = !thinking;
      Parser.aliases = List.rev !aliases; Parser.abbreviations = List.rev !abbrevs }
  end

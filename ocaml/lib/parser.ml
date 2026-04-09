type runner_info = {
  binary : string;
  extra_args : string list;
  thinking_flags : (int * string list) list;
  provider_flag : string;
  model_flag : string;
  agent_flag : string;
}

type parsed_args = {
  runner : string option;
  thinking : int option;
  provider : string option;
  model : string option;
  alias : string option;
  prompt : string;
}

type alias_def = {
  ad_runner : string option;
  ad_thinking : int option;
  ad_provider : string option;
  ad_model : string option;
  ad_agent : string option;
}

type ccc_config = {
  default_runner : string;
  default_provider : string;
  default_model : string;
  default_thinking : int option;
  aliases : (string * alias_def) list;
  abbreviations : (string * string) list;
}

exception Empty_prompt

let default_config = {
  default_runner = "oc";
  default_provider = "";
  default_model = "";
  default_thinking = None;
  aliases = [];
  abbreviations = [];
}

let runner_registry : (string, runner_info) Hashtbl.t = Hashtbl.create 16

let () =
  let opencode = {
    binary = "opencode";
    extra_args = ["run"];
    thinking_flags = [];
    provider_flag = "";
    model_flag = "";
    agent_flag = "--agent";
  } in
  let claude = {
    binary = "claude";
    extra_args = [];
    thinking_flags = [
      (0, ["--thinking"; "disabled"]);
      (1, ["--thinking"; "enabled"; "--effort"; "low"]);
      (2, ["--thinking"; "enabled"; "--effort"; "medium"]);
      (3, ["--thinking"; "enabled"; "--effort"; "high"]);
      (4, ["--thinking"; "enabled"; "--effort"; "max"]);
    ];
    provider_flag = "";
    model_flag = "--model";
    agent_flag = "--agent";
  } in
  let kimi = {
    binary = "kimi";
    extra_args = [];
    thinking_flags = [
      (0, ["--no-thinking"]);
      (1, ["--thinking"]);
      (2, ["--thinking"]);
      (3, ["--thinking"]);
      (4, ["--thinking"]);
    ];
    provider_flag = "";
    model_flag = "--model";
    agent_flag = "--agent";
  } in
  let codex = {
    binary = "codex";
    extra_args = [];
    thinking_flags = [];
    provider_flag = "";
    model_flag = "--model";
    agent_flag = "";
  } in
  let roocode = {
    binary = "roocode";
    extra_args = [];
    thinking_flags = [];
    provider_flag = "";
    model_flag = "--model";
    agent_flag = "";
  } in
  let crush = {
    binary = "crush";
    extra_args = [];
    thinking_flags = [];
    provider_flag = "";
    model_flag = "";
    agent_flag = "";
  } in
  Hashtbl.replace runner_registry "opencode" opencode;
  Hashtbl.replace runner_registry "oc" opencode;
  Hashtbl.replace runner_registry "claude" claude;
  Hashtbl.replace runner_registry "cc" claude;
  Hashtbl.replace runner_registry "c" codex;
  Hashtbl.replace runner_registry "cx" codex;
  Hashtbl.replace runner_registry "kimi" kimi;
  Hashtbl.replace runner_registry "k" kimi;
  Hashtbl.replace runner_registry "codex" codex;
  Hashtbl.replace runner_registry "rc" roocode;
  Hashtbl.replace runner_registry "roocode" roocode;
  Hashtbl.replace runner_registry "crush" crush;
  Hashtbl.replace runner_registry "cr" crush

let valid_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9') || c = '_' || c = '-'

let valid_model_char c = valid_ident_char c || c = '.'

let is_runner_selector s =
  let lower = String.lowercase_ascii s in
  List.exists (fun v -> lower = v) [
    "oc"; "cc"; "c"; "cx"; "k"; "rc"; "cr";
    "codex"; "claude"; "opencode"; "kimi";
    "roocode"; "crush"; "pi";
  ]

let parse_thinking s =
  if String.length s = 2 && s.[0] = '+'
  then match s.[1] with
    | '0' -> Some 0 | '1' -> Some 1 | '2' -> Some 2
    | '3' -> Some 3 | '4' -> Some 4 | _ -> None
  else None

let parse_provider_model s =
  let n = String.length s in
  if n > 2 && s.[0] = ':' then
    let rest = String.sub s 1 (n - 1) in
    match String.index_opt rest ':' with
    | None -> None
    | Some i ->
      let provider = String.sub rest 0 i in
      let model = String.sub rest (i + 1) (String.length rest - i - 1) in
      if String.length provider > 0 && String.for_all valid_ident_char provider
         && String.length model > 0 && String.for_all valid_model_char model
      then Some (provider, model)
      else None
  else None

let parse_model_only s =
  let n = String.length s in
  if n > 1 && s.[0] = ':' then
    let rest = String.sub s 1 (n - 1) in
    if String.contains rest ':' then None
    else if String.length rest > 0 && String.for_all valid_model_char rest
    then Some rest
    else None
  else None

let parse_alias_token s =
  let n = String.length s in
  if n > 1 && s.[0] = '@' then
    let name = String.sub s 1 (n - 1) in
    if String.length name > 0 && String.for_all valid_ident_char name
    then Some name
    else None
  else None

let parse_args argv =
  let runner = ref None in
  let thinking = ref None in
  let provider = ref None in
  let model = ref None in
  let alias = ref None in
  let positional = ref [] in
  List.iter (fun token ->
    if !runner = None && !positional = [] && is_runner_selector token then
      runner := Some (String.lowercase_ascii token)
    else if !positional = [] then begin
      match parse_thinking token with
      | Some n -> thinking := Some n
      | None ->
        match parse_provider_model token with
        | Some (p, m) -> provider := Some p; model := Some m
        | None ->
          match parse_model_only token with
          | Some m -> model := Some m
          | None ->
            match parse_alias_token token with
            | Some a when !alias = None -> alias := Some a
            | _ -> positional := token :: !positional
    end else
      positional := token :: !positional
  ) argv;
  {
    runner = !runner;
    thinking = !thinking;
    provider = !provider;
    model = !model;
    alias = !alias;
    prompt = String.concat " " (List.rev !positional);
  }

let resolve_runner_name name config =
  match name with
  | None -> config.default_runner
  | Some n ->
    match List.assoc_opt n config.abbreviations with
    | Some expanded -> expanded
    | None -> n

let resolve_command parsed config_opt =
  let config = match config_opt with Some c -> c | None -> default_config in
  let runner_name = resolve_runner_name parsed.runner config in
  let info = match Hashtbl.find_opt runner_registry runner_name with
    | Some i -> i
    | None ->
      match Hashtbl.find_opt runner_registry config.default_runner with
      | Some i -> i
      | None ->
        match Hashtbl.find_opt runner_registry "opencode" with
        | Some i -> i
        | None -> assert false
  in
  let alias_def = match parsed.alias with
    | Some a -> List.assoc_opt a config.aliases
    | None -> None
  in
  let effective_info = match alias_def with
    | Some ad ->
      begin match ad.ad_runner with
      | Some r when parsed.runner = None ->
        let resolved = resolve_runner_name (Some r) config in
        begin match Hashtbl.find_opt runner_registry resolved with
        | Some i -> i
        | None -> info
        end
      | _ -> info
      end
    | None -> info
  in
  let argv_base = effective_info.binary :: effective_info.extra_args in
  let effective_thinking = match parsed.thinking with
    | Some t -> Some t
    | None ->
      (match alias_def with
       | Some ad ->
         (match ad.ad_thinking with Some t -> Some t | None -> config.default_thinking)
       | None -> config.default_thinking)
  in
  let argv_thinking = match effective_thinking with
    | Some n ->
      begin match List.assoc_opt n effective_info.thinking_flags with
      | Some flags -> flags
      | None -> []
      end
    | None -> []
  in
  let effective_provider = match parsed.provider with
    | Some p -> p
    | None ->
      match alias_def with
      | Some ad ->
        begin match ad.ad_provider with
        | Some p when p <> "" -> p
        | _ -> config.default_provider
        end
      | None -> config.default_provider
  in
  let effective_model = match parsed.model with
    | Some m -> m
    | None ->
      match alias_def with
      | Some ad ->
        begin match ad.ad_model with
        | Some m when m <> "" -> m
        | _ -> config.default_model
        end
      | None -> config.default_model
  in
  let argv_model =
    if effective_model <> "" && effective_info.model_flag <> ""
    then [effective_info.model_flag; effective_model]
    else []
  in
  let warnings = ref [] in
  let argv_agent =
    match alias_def with
    | Some ad ->
      begin match ad.ad_agent with
      | Some agent when agent <> "" ->
        if effective_info.agent_flag <> "" then
          [effective_info.agent_flag; agent]
        else begin
          warnings := Printf.sprintf
            "warning: runner \"%s\" does not support agents; ignoring @%s"
            effective_info.binary agent :: !warnings;
          []
        end
      | _ -> []
      end
    | None ->
      begin match parsed.alias with
      | Some agent ->
        if effective_info.agent_flag <> "" then
          [effective_info.agent_flag; agent]
        else begin
          warnings := Printf.sprintf
            "warning: runner \"%s\" does not support agents; ignoring @%s"
            effective_info.binary agent :: !warnings;
          []
        end
      | None -> []
      end
  in
  let env =
    if effective_provider <> ""
    then [("CCC_PROVIDER", effective_provider)]
    else []
  in
  let prompt = String.trim parsed.prompt in
  if prompt = "" then raise Empty_prompt;
  let argv = argv_base @ argv_thinking @ argv_model @ argv_agent @ [prompt] in
  (argv, env, List.rev !warnings)

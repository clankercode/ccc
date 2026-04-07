type runner_info = {
  binary : string;
  extra_args : string list;
  thinking_flags : (int * string list) list;
  provider_flag : string;
  model_flag : string;
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

val default_config : ccc_config
val runner_registry : (string, runner_info) Hashtbl.t
val parse_args : string list -> parsed_args
val resolve_command : parsed_args -> ccc_config option -> string list * (string * string) list

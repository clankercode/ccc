type t = {
  argv : string list;
  stdin_text : string option;
  cwd : string option;
  env : (string * string) list;
}

val make :
  ?stdin_text:string option ->
  ?cwd:string option ->
  ?env:(string * string) list ->
  string list -> t

type t = {
  argv : string list;
  exit_code : int;
  stdout : string;
  stderr : string;
}

val make :
  argv:string list ->
  exit_code:int ->
  stdout:string ->
  stderr:string -> t

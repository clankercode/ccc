type t = {
  argv : string list;
  stdin_text : string option;
  cwd : string option;
  env : (string * string) list;
}

let make ?(stdin_text = None) ?(cwd = None) ?(env = []) argv = {
  argv;
  stdin_text;
  cwd;
  env;
}

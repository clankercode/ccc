type t = {
  argv : string list;
  exit_code : int;
  stdout : string;
  stderr : string;
}

let make ~argv ~exit_code ~stdout ~stderr = {
  argv;
  exit_code;
  stdout;
  stderr;
}

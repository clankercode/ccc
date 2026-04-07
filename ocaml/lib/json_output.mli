type tool_call = {
  tc_id : string;
  tc_name : string;
  tc_arguments : string;
}

type tool_result = {
  tr_tool_call_id : string;
  tr_content : string;
  tr_is_error : bool;
}

type json_event = {
  je_event_type : string;
  je_text : string;
  je_thinking : string;
  je_tool_call : tool_call option;
  je_tool_result : tool_result option;
}

type parsed_json_output = {
  schema_name : string;
  events : json_event list;
  final_text : string;
  session_id : string;
  error_text : string;
  cost_usd : float;
  duration_ms : int;
}

val parse_opencode_json : string -> parsed_json_output
val parse_claude_code_json : string -> parsed_json_output
val parse_kimi_json : string -> parsed_json_output
val parse_json_output : string -> string -> parsed_json_output
val render_parsed : parsed_json_output -> string

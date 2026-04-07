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

type json_value =
  | Jnull
  | Jbool of bool
  | Jnumber of float
  | Jstring of string
  | Jarray of json_value list
  | Jobject of (string * json_value) list

exception Json_parse_error

let parse_json s =
  let len = String.length s in
  let pos = ref 0 in
  let skip_ws () =
    while !pos < len &&
      (let c = s.[!pos] in c = ' ' || c = '\t' || c = '\r' || c = '\n')
    do incr pos done
  in
  let peek () = if !pos < len then s.[!pos] else '\000' in
  let advance () = incr pos in
  let parse_string () =
    skip_ws ();
    if peek () <> '"' then raise Json_parse_error;
    advance ();
    let buf = Buffer.create 64 in
    while peek () <> '"' do
      if !pos >= len then raise Json_parse_error;
      let c = peek () in
      if c = '\\' then begin
        advance ();
        match peek () with
        | '"' -> Buffer.add_char buf '"'; advance ()
        | '\\' -> Buffer.add_char buf '\\'; advance ()
        | '/' -> Buffer.add_char buf '/'; advance ()
        | 'n' -> Buffer.add_char buf '\n'; advance ()
        | 't' -> Buffer.add_char buf '\t'; advance ()
        | 'r' -> Buffer.add_char buf '\r'; advance ()
        | _ -> advance ()
      end else begin
        Buffer.add_char buf c;
        advance ()
      end
    done;
    advance ();
    Buffer.contents buf
  in
  let parse_number () =
    let start = !pos in
    if peek () = '-' then advance ();
    while !pos < len && s.[!pos] >= '0' && s.[!pos] <= '9' do advance () done;
    if peek () = '.' then begin
      advance ();
      while !pos < len && s.[!pos] >= '0' && s.[!pos] <= '9' do advance () done
    end;
    let s = String.sub s start (!pos - start) in
    try Jnumber (float_of_string s)
    with _ -> Jnumber 0.0
  in
  let rec parse_value () =
    skip_ws ();
    match peek () with
    | '"' -> Jstring (parse_string ())
    | 't' ->
      advance (); advance (); advance (); advance ();
      Jbool true
    | 'f' ->
      for _ = 1 to 5 do advance () done;
      Jbool false
    | 'n' ->
      for _ = 1 to 4 do advance () done;
      Jnull
    | '{' -> parse_object ()
    | '[' -> parse_array ()
    | c when (c >= '0' && c <= '9') || c = '-' -> parse_number ()
    | _ -> raise Json_parse_error
  and parse_object () =
    advance ();
    skip_ws ();
    let pairs = ref [] in
    if peek () <> '}' then begin
      let continue = ref true in
      while !continue do
        let key = parse_string () in
        skip_ws ();
        if peek () = ':' then advance ();
        skip_ws ();
        let value = parse_value () in
        pairs := (key, value) :: !pairs;
        skip_ws ();
        if peek () = ',' then advance ()
        else continue := false
      done
    end;
    skip_ws ();
    if peek () = '}' then advance ();
    Jobject (List.rev !pairs)
  and parse_array () =
    advance ();
    skip_ws ();
    let items = ref [] in
    if peek () <> ']' then begin
      let continue = ref true in
      while !continue do
        items := parse_value () :: !items;
        skip_ws ();
        if peek () = ',' then advance ()
        else continue := false
      done
    end;
    skip_ws ();
    if peek () = ']' then advance ();
    Jarray (List.rev !items)
  in
  let result = parse_value () in
  result

let obj_get obj key =
  List.assoc_opt key obj

let obj_get_string obj key =
  match obj_get obj key with
  | Some (Jstring s) -> s
  | _ -> ""

let obj_get_bool obj key =
  match obj_get obj key with
  | Some (Jbool b) -> b
  | _ -> false

let obj_get_float obj key =
  match obj_get obj key with
  | Some (Jnumber f) -> f
  | Some (Jstring s) -> (try float_of_string s with _ -> 0.0)
  | _ -> 0.0

let obj_get_int obj key =
  int_of_float (obj_get_float obj key)

let obj_get_object obj key =
  match obj_get obj key with
  | Some (Jobject o) -> o
  | _ -> []

let obj_get_array obj key =
  match obj_get obj key with
  | Some (Jarray a) -> a
  | _ -> []

let obj_has_key obj key =
  obj_get obj key <> None

let empty_event et =
  { je_event_type = et; je_text = ""; je_thinking = "";
    je_tool_call = None; je_tool_result = None }

let text_event et text =
  { je_event_type = et; je_text = text; je_thinking = "";
    je_tool_call = None; je_tool_result = None }

let thinking_event et thinking =
  { je_event_type = et; je_text = ""; je_thinking = thinking;
    je_tool_call = None; je_tool_result = None }

let parse_lines raw_stdout =
  let trimmed = String.trim raw_stdout in
  if trimmed = "" then []
  else begin
    let lines = String.split_on_char '\n' trimmed in
    List.filter_map (fun line ->
      let l = String.trim line in
      if l = "" then None
      else try Some (parse_json l) with _ -> None
    ) lines
  end

let parse_opencode_json raw_stdout =
  let events = ref [] in
  let final_text = ref "" in
  let error_text = ref "" in
  List.iter (function
    | Jobject obj ->
      if obj_has_key obj "response" then begin
        let text = obj_get_string obj "response" in
        final_text := text;
        events := text_event "text" text :: !events
      end else if obj_has_key obj "error" then begin
        let err = obj_get_string obj "error" in
        error_text := err;
        events := text_event "error" err :: !events
      end
    | _ -> ()
  ) (parse_lines raw_stdout);
  { schema_name = "opencode"; events = List.rev !events;
    final_text = !final_text; session_id = ""; error_text = !error_text;
    cost_usd = 0.0; duration_ms = 0 }

let parse_claude_code_json raw_stdout =
  let events = ref [] in
  let final_text = ref "" in
  let session_id = ref "" in
  let error_text = ref "" in
  let cost_usd = ref 0.0 in
  let duration_ms = ref 0 in
  List.iter (function
    | Jobject obj ->
      let msg_type = obj_get_string obj "type" in
      if msg_type = "system" then begin
        let sub = obj_get_string obj "subtype" in
        if sub = "init" then session_id := obj_get_string obj "session_id"
        else if sub = "api_retry" then events := empty_event "system_retry" :: !events
      end else if msg_type = "assistant" then begin
        let msg = obj_get_object obj "message" in
        let content = obj_get_array msg "content" in
        let texts = List.filter_map (function
          | Jobject b when obj_get_string b "type" = "text" ->
            Some (obj_get_string b "text")
          | _ -> None
        ) content in
        if texts <> [] then begin
          let text = String.concat "\n" texts in
          final_text := text;
          events := text_event "assistant" text :: !events
        end
      end else if msg_type = "stream_event" then begin
        let ev = obj_get_object obj "event" in
        let ev_type = obj_get_string ev "type" in
        if ev_type = "content_block_delta" then begin
          let delta = obj_get_object ev "delta" in
          let d_type = obj_get_string delta "type" in
          if d_type = "text_delta" then
            events := text_event "text_delta" (obj_get_string delta "text") :: !events
          else if d_type = "thinking_delta" then
            events := thinking_event "thinking_delta" (obj_get_string delta "thinking") :: !events
          else if d_type = "input_json_delta" then
            events := text_event "tool_input_delta" (obj_get_string delta "partial_json") :: !events
        end else if ev_type = "content_block_start" then begin
          let cb = obj_get_object ev "content_block" in
          let cb_type = obj_get_string cb "type" in
          if cb_type = "thinking" then
            events := empty_event "thinking_start" :: !events
          else if cb_type = "tool_use" then
            let tc = { tc_id = obj_get_string cb "id"; tc_name = obj_get_string cb "name"; tc_arguments = "" } in
            events := { je_event_type = "tool_use_start"; je_text = ""; je_thinking = ""; je_tool_call = Some tc; je_tool_result = None } :: !events
        end
      end else if msg_type = "tool_use" then begin
        let tc = { tc_id = ""; tc_name = obj_get_string obj "tool_name"; tc_arguments = "{}" } in
        events := { je_event_type = "tool_use"; je_text = ""; je_thinking = ""; je_tool_call = Some tc; je_tool_result = None } :: !events
      end else if msg_type = "tool_result" then begin
        let tr = { tr_tool_call_id = obj_get_string obj "tool_use_id"; tr_content = obj_get_string obj "content"; tr_is_error = obj_get_bool obj "is_error" } in
        events := { je_event_type = "tool_result"; je_text = ""; je_thinking = ""; je_tool_call = None; je_tool_result = Some tr } :: !events
      end else if msg_type = "result" then begin
        let sub = obj_get_string obj "subtype" in
        if sub = "success" then begin
          let res = obj_get_string obj "result" in
          if res <> "" then final_text := res;
          cost_usd := obj_get_float obj "cost_usd";
          duration_ms := obj_get_int obj "duration_ms";
          events := text_event "result" !final_text :: !events
        end else if sub = "error" then begin
          let err = obj_get_string obj "error" in
          error_text := err;
          events := text_event "error" err :: !events
        end
      end
    | _ -> ()
  ) (parse_lines raw_stdout);
  { schema_name = "claude-code"; events = List.rev !events;
    final_text = !final_text; session_id = !session_id; error_text = !error_text;
    cost_usd = !cost_usd; duration_ms = !duration_ms }

let kimi_passthrough = [
  "TurnBegin"; "StepBegin"; "StepInterrupted"; "TurnEnd";
  "StatusUpdate"; "HookTriggered"; "HookResolved"; "ApprovalRequest";
  "SubagentEvent"; "ToolCallRequest"
]

let is_kimi_passthrough s =
  List.exists (fun p -> p = s) kimi_passthrough

let parse_kimi_json raw_stdout =
  let events = ref [] in
  let final_text = ref "" in
  List.iter (function
    | Jobject obj ->
      let wire_type = obj_get_string obj "type" in
      if wire_type <> "" && is_kimi_passthrough wire_type then
        events := empty_event (String.lowercase_ascii wire_type) :: !events
      else begin
        let role = obj_get_string obj "role" in
        if role = "assistant" then begin
          (match obj_get obj "content" with
           | Some (Jstring s) ->
             final_text := s;
             events := text_event "assistant" s :: !events
           | Some (Jarray parts) ->
             let texts = ref [] in
             List.iter (function
               | Jobject p ->
                 let pt = obj_get_string p "type" in
                 if pt = "text" then texts := obj_get_string p "text" :: !texts
                 else if pt = "think" then
                   events := thinking_event "thinking" (obj_get_string p "think") :: !events
               | _ -> ()
             ) parts;
             let ts = List.rev !texts in
             if ts <> [] then begin
               let text = String.concat "\n" ts in
               final_text := text;
               events := text_event "assistant" text :: !events
             end
           | _ -> ());
          let tcs = obj_get_array obj "tool_calls" in
          List.iter (function
            | Jobject tc ->
              let fn = obj_get_object tc "function" in
              let t = { tc_id = obj_get_string tc "id"; tc_name = obj_get_string fn "name"; tc_arguments = obj_get_string fn "arguments" } in
              events := { je_event_type = "tool_call"; je_text = ""; je_thinking = ""; je_tool_call = Some t; je_tool_result = None } :: !events
            | _ -> ()
          ) tcs
        end else if role = "tool" then begin
          let content = obj_get_array obj "content" in
            let texts = List.filter_map (function
            | Jobject p when obj_get_string p "type" = "text" ->
              let t = obj_get_string p "text" in
              let is_sys = String.length t >= 8 && String.sub t 0 8 = "<system>" in
              if is_sys then None else Some t
            | _ -> None
          ) content in
          let tr = { tr_tool_call_id = obj_get_string obj "tool_call_id"; tr_content = String.concat "\n" texts; tr_is_error = false } in
          events := { je_event_type = "tool_result"; je_text = ""; je_thinking = ""; je_tool_call = None; je_tool_result = Some tr } :: !events
        end
      end
    | _ -> ()
  ) (parse_lines raw_stdout);
  { schema_name = "kimi"; events = List.rev !events;
    final_text = !final_text; session_id = ""; error_text = "";
    cost_usd = 0.0; duration_ms = 0 }

let parse_json_output raw_stdout schema =
  match schema with
  | "opencode" -> parse_opencode_json raw_stdout
  | "claude-code" -> parse_claude_code_json raw_stdout
  | "kimi" -> parse_kimi_json raw_stdout
  | _ -> { schema_name = schema; events = []; final_text = ""; session_id = "";
           error_text = "unknown schema: " ^ schema; cost_usd = 0.0; duration_ms = 0 }

let render_parsed output =
  let parts = List.filter_map (fun ev ->
    match ev.je_event_type with
    | "text" | "assistant" | "result" ->
      if ev.je_text <> "" then Some ev.je_text else None
    | "thinking_delta" | "thinking" ->
      if ev.je_thinking <> "" then Some ("[thinking] " ^ ev.je_thinking) else None
    | "tool_use" ->
      (match ev.je_tool_call with Some tc -> Some ("[tool] " ^ tc.tc_name) | None -> None)
    | "tool_result" ->
      (match ev.je_tool_result with Some tr -> Some ("[tool_result] " ^ tr.tr_content) | None -> None)
    | "error" ->
      if ev.je_text <> "" then Some ("[error] " ^ ev.je_text) else None
    | _ -> None
  ) output.events in
  if parts <> [] then String.concat "\n" parts
  else output.final_text

let () =
  let open Alcotest in
  let open Ccc_lib in
  run "json_output" [
    ("parse_opencode", [
      test_case "response" `Quick (fun () ->
        let r = Json_output.parse_opencode_json {|{"response": "hello"}
|} in
        check int "events" 1 (List.length r.Json_output.events);
        check string "type" "text" (List.hd r.Json_output.events).Json_output.je_event_type;
        check string "text" "hello" (List.hd r.Json_output.events).Json_output.je_text;
        check string "final" "hello" r.Json_output.final_text);

      test_case "error" `Quick (fun () ->
        let r = Json_output.parse_opencode_json {|{"error": "fail"}
|} in
        check string "error" "fail" r.Json_output.error_text;
        check string "type" "error" (List.hd r.Json_output.events).Json_output.je_event_type);

      test_case "skips invalid json" `Quick (fun () ->
        let r = Json_output.parse_opencode_json "bad\n{\"response\": \"ok\"}\n" in
        check int "events" 1 (List.length r.Json_output.events);
        check string "final" "ok" r.Json_output.final_text);

      test_case "empty input" `Quick (fun () ->
        let r = Json_output.parse_opencode_json "" in
        check int "events" 0 (List.length r.Json_output.events));
    ]);

    ("parse_claude_code", [
      test_case "system init" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"system","subtype":"init","session_id":"s1"}
|} in
        check string "session" "s1" r.Json_output.session_id);

      test_case "assistant" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}
|} in
        check int "events" 1 (List.length r.Json_output.events);
        check string "type" "assistant" (List.hd r.Json_output.events).Json_output.je_event_type;
        check string "final" "hi" r.Json_output.final_text);

      test_case "text delta" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"yo"}}}}
|} in
        check string "type" "text_delta" (List.hd r.Json_output.events).Json_output.je_event_type;
        check string "text" "yo" (List.hd r.Json_output.events).Json_output.je_text);

      test_case "tool use" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"tool_use","tool_name":"read","tool_input":{"a":1}}
|} in
        let ev = List.hd r.Json_output.events in
        check string "type" "tool_use" ev.Json_output.je_event_type;
        check string "name" "read" (Option.get ev.Json_output.je_tool_call).Json_output.tc_name);

      test_case "tool result" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"tool_result","tool_use_id":"t1","content":"out","is_error":false}}
|} in
        let tr = Option.get (List.hd r.Json_output.events).Json_output.je_tool_result in
        check string "id" "t1" tr.Json_output.tr_tool_call_id;
        check string "content" "out" tr.Json_output.tr_content;
        check bool "is_error" false tr.Json_output.tr_is_error);

      test_case "result success" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"result","subtype":"success","result":"done","cost_usd":0.1,"duration_ms":500}}
|} in
        check string "final" "done" r.Json_output.final_text;
        check (float 0.001) "cost" 0.1 r.Json_output.cost_usd;
        check int "duration" 500 r.Json_output.duration_ms);

      test_case "result error" `Quick (fun () ->
        let r = Json_output.parse_claude_code_json {|{"type":"result","subtype":"error","error":"boom"}}
|} in
        check string "error" "boom" r.Json_output.error_text);
    ]);

    ("parse_kimi", [
      test_case "assistant text" `Quick (fun () ->
        let r = Json_output.parse_kimi_json {|{"role":"assistant","content":"hello"}
|} in
        check string "type" "assistant" (List.hd r.Json_output.events).Json_output.je_event_type;
        check string "final" "hello" r.Json_output.final_text);

      test_case "tool calls" `Quick (fun () ->
        let r = Json_output.parse_kimi_json {|{"role":"assistant","content":"","tool_calls":[{"id":"1","function":{"name":"bash","arguments":"{}"}}]}}
|} in
        let tc_ev = List.find (fun e -> e.Json_output.je_event_type = "tool_call") r.Json_output.events in
        check string "name" "bash" (Option.get tc_ev.Json_output.je_tool_call).Json_output.tc_name);

      test_case "passthrough" `Quick (fun () ->
        let r = Json_output.parse_kimi_json {|{"type":"TurnBegin"}}
|} in
        check string "type" "turnbegin" (List.hd r.Json_output.events).Json_output.je_event_type);
    ]);

    ("parse_json_output", [
      test_case "dispatches opencode" `Quick (fun () ->
        let r = Json_output.parse_json_output {|{"response":"ok"}
|} "opencode" in
        check string "schema" "opencode" r.Json_output.schema_name;
        check string "final" "ok" r.Json_output.final_text);

      test_case "unknown schema" `Quick (fun () ->
        let r = Json_output.parse_json_output "" "unknown" in
        check bool "has error" true (String.length r.Json_output.error_text > 0));
    ]);

    ("render_parsed", [
      test_case "text events" `Quick (fun () ->
        let r = { Json_output.schema_name = "test"; Json_output.events = [
          { Json_output.je_event_type = "text"; je_text = "hello"; je_thinking = ""; je_tool_call = None; je_tool_result = None };
          { Json_output.je_event_type = "assistant"; je_text = "world"; je_thinking = ""; je_tool_call = None; je_tool_result = None };
        ]; Json_output.final_text = ""; Json_output.session_id = ""; Json_output.error_text = "";
          Json_output.cost_usd = 0.0; Json_output.duration_ms = 0 } in
        check string "render" "hello\nworld" (Json_output.render_parsed r));

      test_case "thinking" `Quick (fun () ->
        let r = { Json_output.schema_name = "test"; Json_output.events = [
          { Json_output.je_event_type = "thinking"; je_text = ""; je_thinking = "hmm"; je_tool_call = None; je_tool_result = None };
        ]; Json_output.final_text = ""; Json_output.session_id = ""; Json_output.error_text = "";
          Json_output.cost_usd = 0.0; Json_output.duration_ms = 0 } in
        check string "render" "[thinking] hmm" (Json_output.render_parsed r));

      test_case "tool use and result" `Quick (fun () ->
        let r = { Json_output.schema_name = "test"; Json_output.events = [
          { Json_output.je_event_type = "tool_use"; je_text = ""; je_thinking = "";
            je_tool_call = Some { Json_output.tc_id = ""; tc_name = "read"; tc_arguments = "" };
            je_tool_result = None };
          { Json_output.je_event_type = "tool_result"; je_text = ""; je_thinking = "";
            je_tool_call = None;
            je_tool_result = Some { Json_output.tr_tool_call_id = ""; tr_content = "output"; tr_is_error = false } };
        ]; Json_output.final_text = ""; Json_output.session_id = ""; Json_output.error_text = "";
          Json_output.cost_usd = 0.0; Json_output.duration_ms = 0 } in
        check string "render" "[tool] read\n[tool_result] output" (Json_output.render_parsed r));

      test_case "fallback" `Quick (fun () ->
        let r = { Json_output.schema_name = "test"; Json_output.events = [];
          Json_output.final_text = "fallback"; Json_output.session_id = ""; Json_output.error_text = "";
          Json_output.cost_usd = 0.0; Json_output.duration_ms = 0 } in
        check string "render" "fallback" (Json_output.render_parsed r));

      test_case "error" `Quick (fun () ->
        let r = { Json_output.schema_name = "test"; Json_output.events = [
          { Json_output.je_event_type = "error"; je_text = "oops"; je_thinking = ""; je_tool_call = None; je_tool_result = None };
        ]; Json_output.final_text = ""; Json_output.session_id = ""; Json_output.error_text = "";
          Json_output.cost_usd = 0.0; Json_output.duration_ms = 0 } in
        check string "render" "[error] oops" (Json_output.render_parsed r));
    ]);
  ]

{-# LANGUAGE OverloadedStrings #-}
module JsonOutputSpec (jsonOutputSpec) where

import qualified Data.Aeson.KeyMap as KM
import qualified Data.Text as T
import CallCodingClis.JsonOutput
import Test.Hspec

jsonOutputSpec :: Spec
jsonOutputSpec = do
  describe "parseOpencodeJson" $ do
    it "parses a response line" $ do
      let r = parseOpencodeJson "{\"response\": \"hello world\"}"
      pjoSchemaName r `shouldBe` "opencode"
      pjoFinalText r `shouldBe` "hello world"
      length (pjoEvents r) `shouldBe` 1
      jeEventType (head (pjoEvents r)) `shouldBe` "text"

    it "parses an error line" $ do
      let r = parseOpencodeJson "{\"error\": \"something went wrong\"}"
      pjoError r `shouldBe` "something went wrong"
      length (pjoEvents r) `shouldBe` 1
      jeEventType (head (pjoEvents r)) `shouldBe` "error"

    it "skips invalid JSON lines" $ do
      let r = parseOpencodeJson "not json\n{\"response\": \"ok\"}"
      length (pjoEvents r) `shouldBe` 1
      pjoFinalText r `shouldBe` "ok"

    it "handles multiple lines with last response winning" $ do
      let r = parseOpencodeJson "{\"response\": \"first\"}\n{\"response\": \"second\"}"
      pjoFinalText r `shouldBe` "second"
      length (pjoEvents r) `shouldBe` 2

    it "handles empty input" $ do
      let r = parseOpencodeJson ""
      pjoEvents r `shouldBe` []

  describe "parseClaudeCodeJson" $ do
    it "parses system init" $ do
      let r = parseClaudeCodeJson "{\"type\": \"system\", \"subtype\": \"init\", \"session_id\": \"abc123\"}"
      pjoSessionId r `shouldBe` "abc123"

    it "parses assistant message with text blocks" $ do
      let r = parseClaudeCodeJson "{\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"text\", \"text\": \"hello\"}], \"usage\": {\"input_tokens\": 10}}}"
      pjoFinalText r `shouldBe` "hello"
      length (pjoEvents r) `shouldBe` 1
      jeEventType (head (pjoEvents r)) `shouldBe` "assistant"

    it "parses stream text_delta" $ do
      let r = parseClaudeCodeJson "{\"type\": \"stream_event\", \"event\": {\"type\": \"content_block_delta\", \"delta\": {\"type\": \"text_delta\", \"text\": \"hi\"}}}"
      jeEventType (head (pjoEvents r)) `shouldBe` "text_delta"
      jeText (head (pjoEvents r)) `shouldBe` "hi"

    it "parses stream thinking_delta" $ do
      let r = parseClaudeCodeJson "{\"type\": \"stream_event\", \"event\": {\"type\": \"content_block_delta\", \"delta\": {\"type\": \"thinking_delta\", \"thinking\": \"hmm\"}}}"
      jeEventType (head (pjoEvents r)) `shouldBe` "thinking_delta"
      jeThinking (head (pjoEvents r)) `shouldBe` "hmm"

    it "parses tool_use" $ do
      let r = parseClaudeCodeJson "{\"type\": \"tool_use\", \"tool_name\": \"read_file\", \"tool_input\": {\"path\": \"/foo\"}}"
      jeEventType (head (pjoEvents r)) `shouldBe` "tool_use"
      let Just tc = jeToolCall (head (pjoEvents r))
      tcName tc `shouldBe` "read_file"

    it "parses tool_result" $ do
      let r = parseClaudeCodeJson "{\"type\": \"tool_result\", \"tool_use_id\": \"tu1\", \"content\": \"file contents\", \"is_error\": false}"
      jeEventType (head (pjoEvents r)) `shouldBe` "tool_result"
      let Just tr = jeToolResult (head (pjoEvents r))
      trToolCallId tr `shouldBe` "tu1"
      trContent tr `shouldBe` "file contents"
      trIsError tr `shouldBe` False

    it "parses result success" $ do
      let r = parseClaudeCodeJson "{\"type\": \"result\", \"subtype\": \"success\", \"result\": \"done\", \"cost_usd\": 0.05, \"duration_ms\": 1200}"
      pjoFinalText r `shouldBe` "done"
      pjoCostUsd r `shouldBe` 0.05
      pjoDurationMs r `shouldBe` 1200

    it "parses result error" $ do
      let r = parseClaudeCodeJson "{\"type\": \"result\", \"subtype\": \"error\", \"error\": \"fail\"}"
      pjoError r `shouldBe` "fail"

    it "parses tool_use_start from stream_event" $ do
      let r = parseClaudeCodeJson "{\"type\": \"stream_event\", \"event\": {\"type\": \"content_block_start\", \"content_block\": {\"type\": \"tool_use\", \"id\": \"tc1\", \"name\": \"bash\"}}}"
      jeEventType (head (pjoEvents r)) `shouldBe` "tool_use_start"
      let Just tc = jeToolCall (head (pjoEvents r))
      tcName tc `shouldBe` "bash"

  describe "parseKimiJson" $ do
    it "parses passthrough TurnBegin" $ do
      let r = parseKimiJson "{\"type\": \"TurnBegin\"}"
      jeEventType (head (pjoEvents r)) `shouldBe` "turnbegin"

    it "parses assistant with string content" $ do
      let r = parseKimiJson "{\"role\": \"assistant\", \"content\": \"hello there\"}"
      pjoFinalText r `shouldBe` "hello there"
      jeEventType (head (pjoEvents r)) `shouldBe` "assistant"

    it "parses assistant with array content" $ do
      let r = parseKimiJson "{\"role\": \"assistant\", \"content\": [{\"type\": \"text\", \"text\": \"result\"}, {\"type\": \"think\", \"think\": \"reasoning\"}]}"
      length (pjoEvents r) `shouldBe` 2
      let thinkingEv = head [e | e <- pjoEvents r, jeEventType e == "thinking"]
      jeThinking thinkingEv `shouldBe` "reasoning"

    it "parses tool calls" $ do
      let r = parseKimiJson "{\"role\": \"assistant\", \"content\": \"\", \"tool_calls\": [{\"id\": \"tc1\", \"function\": {\"name\": \"edit\", \"arguments\": \"{\\\"file\\\": \\\"a\\\"}\"}}]}"
      let tcEvents = [e | e <- pjoEvents r, jeEventType e == "tool_call"]
      length tcEvents `shouldBe` 1
      let Just tc = jeToolCall (head tcEvents)
      tcName tc `shouldBe` "edit"

    it "parses tool result filtering system tags" $ do
      let r = parseKimiJson "{\"role\": \"tool\", \"tool_call_id\": \"tc1\", \"content\": [{\"type\": \"text\", \"text\": \"<system>internal</system>\"}, {\"type\": \"text\", \"text\": \"visible output\"}]}"
      let Just tr = jeToolResult (head (pjoEvents r))
      trContent tr `shouldBe` "visible output"
      trToolCallId tr `shouldBe` "tc1"

  describe "parseJsonOutput" $ do
    it "dispatches to opencode" $ do
      let r = parseJsonOutput "{\"response\": \"hi\"}" "opencode"
      pjoSchemaName r `shouldBe` "opencode"
      pjoFinalText r `shouldBe` "hi"

    it "dispatches to claude-code" $ do
      let r = parseJsonOutput "{\"type\": \"system\", \"subtype\": \"init\", \"session_id\": \"s1\"}" "claude-code"
      pjoSessionId r `shouldBe` "s1"

    it "returns error for unknown schema" $ do
      let r = parseJsonOutput "" "unknown"
      pjoError r `shouldSatisfy` T.isInfixOf "unknown schema"

  describe "renderParsed" $ do
    it "renders text events" $ do
      let output = ParsedJsonOutput "opencode" [JsonEvent "text" "hello" "" Nothing Nothing KM.empty] "hello" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "hello"

    it "renders thinking events" $ do
      let output = ParsedJsonOutput "test" [JsonEvent "thinking" "" "deep thoughts" Nothing Nothing KM.empty] "" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "[thinking] deep thoughts"

    it "renders tool use events" $ do
      let output = ParsedJsonOutput "test" [JsonEvent "tool_use" "" "" (Just (ToolCall "" "bash" "")) Nothing KM.empty] "" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "[tool] bash"

    it "renders error events" $ do
      let output = ParsedJsonOutput "test" [JsonEvent "error" "oops" "" Nothing Nothing KM.empty] "" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "[error] oops"

    it "falls back to final_text when no renderable events" $ do
      let output = ParsedJsonOutput "test" [JsonEvent "system_retry" "" "" Nothing Nothing KM.empty] "fallback" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "fallback"

    it "renders tool_result events" $ do
      let output = ParsedJsonOutput "test" [JsonEvent "tool_result" "" "" Nothing (Just (ToolResult "" "file data" False)) KM.empty] "" "" "" KM.empty 0.0 0 []
      renderParsed output `shouldBe` "[tool_result] file data"

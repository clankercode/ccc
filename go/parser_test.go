package ccc

import (
	"strings"
	"testing"
)

func strPtr(s string) *string { return &s }
func intPtr(i int) *int       { return &i }

func assertArgv(t *testing.T, expected, actual []string) {
	t.Helper()
	if len(expected) != len(actual) {
		t.Fatalf("argv length: expected %d, got %d\nexpected: %v\nactual: %v", len(expected), len(actual), expected, actual)
	}
	for i := range expected {
		if expected[i] != actual[i] {
			t.Fatalf("argv[%d]: expected %q, got %q\nexpected: %v\nactual: %v", i, expected[i], actual[i], expected, actual)
		}
	}
}

func TestParseArgs_PromptOnly(t *testing.T) {
	p := ParseArgs([]string{"hello world"})
	if p.Runner != nil || p.Thinking != nil || p.Provider != nil || p.Model != nil || p.Alias != nil {
		t.Fatalf("expected all selectors nil, got runner=%v thinking=%v provider=%v model=%v alias=%v",
			p.Runner, p.Thinking, p.Provider, p.Model, p.Alias)
	}
	if p.Prompt != "hello world" {
		t.Fatalf("expected prompt %q, got %q", "hello world", p.Prompt)
	}
}

func TestParseArgs_RunnerSelector(t *testing.T) {
	p := ParseArgs([]string{"claude", "do stuff"})
	if p.Runner == nil || *p.Runner != "claude" {
		t.Fatalf("expected runner=claude, got %v", p.Runner)
	}
	if p.Prompt != "do stuff" {
		t.Fatalf("expected prompt %q, got %q", "do stuff", p.Prompt)
	}
}

func TestParseArgs_RunnerSelectorCodexAliases(t *testing.T) {
	for _, runner := range []string{"c", "cx"} {
		p := ParseArgs([]string{runner, "fix bug"})
		if p.Runner == nil || *p.Runner != runner {
			t.Fatalf("expected runner=%s, got %v", runner, p.Runner)
		}
		if p.Prompt != "fix bug" {
			t.Fatalf("expected prompt %q, got %q", "fix bug", p.Prompt)
		}
	}
}

func TestParseArgs_RunnerSelectorRooCode(t *testing.T) {
	p := ParseArgs([]string{"rc", "fix bug"})
	if p.Runner == nil || *p.Runner != "rc" {
		t.Fatalf("expected runner=rc, got %v", p.Runner)
	}
	if p.Prompt != "fix bug" {
		t.Fatalf("expected prompt %q, got %q", "fix bug", p.Prompt)
	}
}

func TestParseArgs_Thinking(t *testing.T) {
	p := ParseArgs([]string{"+2", "think hard"})
	if p.Thinking == nil || *p.Thinking != 2 {
		t.Fatalf("expected thinking=2, got %v", p.Thinking)
	}
	if p.Prompt != "think hard" {
		t.Fatalf("expected prompt %q, got %q", "think hard", p.Prompt)
	}
}

func TestParseArgs_ProviderModel(t *testing.T) {
	p := ParseArgs([]string{":anthropic:claude-3", "hi"})
	if p.Provider == nil || *p.Provider != "anthropic" {
		t.Fatalf("expected provider=anthropic, got %v", p.Provider)
	}
	if p.Model == nil || *p.Model != "claude-3" {
		t.Fatalf("expected model=claude-3, got %v", p.Model)
	}
	if p.Prompt != "hi" {
		t.Fatalf("expected prompt %q, got %q", "hi", p.Prompt)
	}
}

func TestParseArgs_ModelOnly(t *testing.T) {
	p := ParseArgs([]string{":gpt-4o", "hi"})
	if p.Model == nil || *p.Model != "gpt-4o" {
		t.Fatalf("expected model=gpt-4o, got %v", p.Model)
	}
	if p.Provider != nil {
		t.Fatalf("expected provider nil, got %v", p.Provider)
	}
}

func TestParseArgs_Alias(t *testing.T) {
	p := ParseArgs([]string{"@fast", "do it"})
	if p.Alias == nil || *p.Alias != "fast" {
		t.Fatalf("expected alias=fast, got %v", p.Alias)
	}
	if p.Prompt != "do it" {
		t.Fatalf("expected prompt %q, got %q", "do it", p.Prompt)
	}
}

func TestParseArgs_FullCombo(t *testing.T) {
	p := ParseArgs([]string{"claude", "+3", ":anthropic:opus", "hello"})
	if p.Runner == nil || *p.Runner != "claude" {
		t.Fatalf("expected runner=claude, got %v", p.Runner)
	}
	if p.Thinking == nil || *p.Thinking != 3 {
		t.Fatalf("expected thinking=3, got %v", p.Thinking)
	}
	if p.Provider == nil || *p.Provider != "anthropic" {
		t.Fatalf("expected provider=anthropic, got %v", p.Provider)
	}
	if p.Model == nil || *p.Model != "opus" {
		t.Fatalf("expected model=opus, got %v", p.Model)
	}
	if p.Prompt != "hello" {
		t.Fatalf("expected prompt %q, got %q", "hello", p.Prompt)
	}
}

func TestParseArgs_MultiplePositional(t *testing.T) {
	p := ParseArgs([]string{"hello", "beautiful", "world"})
	if p.Prompt != "hello beautiful world" {
		t.Fatalf("expected prompt %q, got %q", "hello beautiful world", p.Prompt)
	}
}

func TestParseArgs_RunnerAfterPositional(t *testing.T) {
	p := ParseArgs([]string{"hello", "claude"})
	if p.Runner != nil {
		t.Fatalf("expected runner nil, got %v", p.Runner)
	}
	if p.Prompt != "hello claude" {
		t.Fatalf("expected prompt %q, got %q", "hello claude", p.Prompt)
	}
}

func TestParseArgs_CaseInsensitiveRunner(t *testing.T) {
	p := ParseArgs([]string{"CLAUDE", "hi"})
	if p.Runner == nil || *p.Runner != "claude" {
		t.Fatalf("expected runner=claude, got %v", p.Runner)
	}
}

func TestParseArgs_AliasAndModel(t *testing.T) {
	p := ParseArgs([]string{"@my", ":gpt-4", "prompt"})
	if p.Alias == nil || *p.Alias != "my" {
		t.Fatalf("expected alias=my, got %v", p.Alias)
	}
	if p.Model == nil || *p.Model != "gpt-4" {
		t.Fatalf("expected model=gpt-4, got %v", p.Model)
	}
	if p.Prompt != "prompt" {
		t.Fatalf("expected prompt %q, got %q", "prompt", p.Prompt)
	}
}

func TestResolveCommand_DefaultRunner(t *testing.T) {
	argv, env, warnings, err := ResolveCommand(ParsedArgs{Prompt: "hello"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"opencode", "run", "hello"}, argv)
	if len(env) != 0 {
		t.Fatalf("expected empty env, got %v", env)
	}
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_ClaudeRunner(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_CodexRunner(t *testing.T) {
	for _, runner := range []string{"c", "cx"} {
		argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr(runner), Prompt: "hi"}, nil)
		if err != nil {
			t.Fatalf("unexpected error for %s: %v", runner, err)
		}
		if argv[0] != "codex" {
			t.Fatalf("expected codex binary for %s, got %v", runner, argv)
		}
		if len(warnings) != 0 {
			t.Fatalf("expected no warnings for %s, got %v", runner, warnings)
		}
	}
}

func TestResolveCommand_RooCodeRunner(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("rc"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"roocode", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_ThinkingFlags(t *testing.T) {
	argv, _, _, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Thinking: intPtr(2), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--thinking", "medium", "hi"}, argv)
}

func TestResolveCommand_ModelFlag(t *testing.T) {
	argv, _, _, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Model: strPtr("gpt-4"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--model", "gpt-4", "hi"}, argv)
}

func TestResolveCommand_ProviderEnv(t *testing.T) {
	_, env, _, err := ResolveCommand(ParsedArgs{Provider: strPtr("anthropic"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if env["CCC_PROVIDER"] != "anthropic" {
		t.Fatalf("expected CCC_PROVIDER=anthropic, got %v", env)
	}
}

func TestResolveCommand_EmptyPromptError(t *testing.T) {
	_, _, _, err := ResolveCommand(ParsedArgs{}, nil)
	if err == nil {
		t.Fatal("expected error for empty prompt")
	}
	if !strings.Contains(err.Error(), "prompt must not be empty") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestResolveCommand_ConfigDefaultsRunner(t *testing.T) {
	cfg := &CccConfig{DefaultRunner: "claude", Aliases: map[string]AliasDef{}, Abbreviations: map[string]string{}}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_ConfigDefaultsModel(t *testing.T) {
	cfg := &CccConfig{DefaultModel: "gpt-4", Aliases: map[string]AliasDef{}, Abbreviations: map[string]string{}}
	argv, _, _, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--model", "gpt-4", "hi"}, argv)
}

func TestResolveCommand_ConfigDefaultsThinking(t *testing.T) {
	cfg := &CccConfig{DefaultThinking: intPtr(3), Aliases: map[string]AliasDef{}, Abbreviations: map[string]string{}}
	argv, _, _, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--thinking", "high", "hi"}, argv)
}

func TestResolveCommand_AliasResolution(t *testing.T) {
	cfg := &CccConfig{
		Aliases: map[string]AliasDef{
			"fast": {Runner: strPtr("claude"), Thinking: intPtr(2)},
		},
		Abbreviations: map[string]string{},
	}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Alias: strPtr("fast"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--thinking", "medium", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_NameFallsBackToAgent(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Alias: strPtr("reviewer"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"opencode", "run", "--agent", "reviewer", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestRunnerRegistryAliases(t *testing.T) {
	if RunnerRegistry["c"].Binary != "codex" {
		t.Fatalf("expected c to map to codex, got %q", RunnerRegistry["c"].Binary)
	}
	if RunnerRegistry["cx"].Binary != "codex" {
		t.Fatalf("expected cx to map to codex, got %q", RunnerRegistry["cx"].Binary)
	}
	if RunnerRegistry["rc"].Binary != "roocode" {
		t.Fatalf("expected rc to map to roocode, got %q", RunnerRegistry["rc"].Binary)
	}
}

func TestResolveCommand_AgentWarningUsesRooCodeName(t *testing.T) {
	parsed := ParsedArgs{
		Runner: strPtr("rc"),
		Alias:  strPtr("reviewer"),
		Prompt: "hi",
	}
	_, _, warnings, err := ResolveCommand(parsed, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(warnings) != 1 {
		t.Fatalf("expected one warning, got %v", warnings)
	}
	want := `warning: runner "roocode" does not support agents; ignoring @reviewer`
	if warnings[0] != want {
		t.Fatalf("expected warning %q, got %q", want, warnings[0])
	}
}

func TestResolveCommand_NameFallsBackToAgentForClaude(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("claude"), Alias: strPtr("reviewer"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--agent", "reviewer", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_AliasPresetAgent(t *testing.T) {
	cfg := &CccConfig{
		Aliases: map[string]AliasDef{
			"reviewer": {Agent: strPtr("specialist")},
		},
		Abbreviations: map[string]string{},
	}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Alias: strPtr("reviewer"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"opencode", "run", "--agent", "specialist", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_AgentUnsupportedWarning(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("rc"), Alias: strPtr("reviewer"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"roocode", "hi"}, argv)
	if len(warnings) != 1 {
		t.Fatalf("expected one warning, got %v", warnings)
	}
	want := `warning: runner "roocode" does not support agents; ignoring @reviewer`
	if warnings[0] != want {
		t.Fatalf("expected warning %q, got %q", want, warnings[0])
	}
}

func TestResolveCommand_AliasWithProviderModel(t *testing.T) {
	cfg := &CccConfig{
		DefaultRunner: "claude",
		Aliases: map[string]AliasDef{
			"fast": {Provider: strPtr("anthropic"), Model: strPtr("opus")},
		},
		Abbreviations: map[string]string{},
	}
	argv, env, warnings, err := ResolveCommand(ParsedArgs{Alias: strPtr("fast"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "--model", "opus", "hi"}, argv)
	if env["CCC_PROVIDER"] != "anthropic" {
		t.Fatalf("expected CCC_PROVIDER=anthropic, got %v", env)
	}
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_Abbreviation(t *testing.T) {
	cfg := &CccConfig{
		Abbreviations: map[string]string{"my": "claude"},
		Aliases:       map[string]AliasDef{},
	}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("my"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_NilConfig(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Prompt: "test"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"opencode", "run", "test"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_KimiThinking(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("kimi"), Thinking: intPtr(0), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"kimi", "--no-think", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_CrushRunner(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("crush"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"crush", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_OpencodeIgnoresModel(t *testing.T) {
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("oc"), Model: strPtr("gpt-4"), Prompt: "hi"}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"opencode", "run", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_AliasOverridesRunner(t *testing.T) {
	cfg := &CccConfig{
		Aliases: map[string]AliasDef{
			"fast": {Runner: strPtr("claude")},
		},
		Abbreviations: map[string]string{},
	}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Alias: strPtr("fast"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"claude", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_AliasDoesNotOverrideExplicitRunner(t *testing.T) {
	cfg := &CccConfig{
		Aliases: map[string]AliasDef{
			"fast": {Runner: strPtr("claude")},
		},
		Abbreviations: map[string]string{},
	}
	argv, _, warnings, err := ResolveCommand(ParsedArgs{Runner: strPtr("kimi"), Alias: strPtr("fast"), Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertArgv(t, []string{"kimi", "hi"}, argv)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

func TestResolveCommand_ProviderEmptyDefault(t *testing.T) {
	cfg := &CccConfig{DefaultProvider: "", Aliases: map[string]AliasDef{}, Abbreviations: map[string]string{}}
	_, env, warnings, err := ResolveCommand(ParsedArgs{Prompt: "hi"}, cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := env["CCC_PROVIDER"]; ok {
		t.Fatalf("expected no CCC_PROVIDER in env, got %v", env)
	}
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
}

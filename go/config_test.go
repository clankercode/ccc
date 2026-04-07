package ccc

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfig_MissingFile(t *testing.T) {
	cfg := LoadConfig(filepath.Join(t.TempDir(), "nonexistent.toml"))
	if cfg.DefaultRunner != "oc" {
		t.Fatalf("expected default runner 'oc', got %q", cfg.DefaultRunner)
	}
	if len(cfg.Aliases) != 0 {
		t.Fatalf("expected no aliases, got %v", cfg.Aliases)
	}
}

func TestLoadConfig_Defaults(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	content := `
[defaults]
runner = "claude"
provider = "anthropic"
model = "gpt-4"
thinking = 3
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := LoadConfig(path)
	if cfg.DefaultRunner != "claude" {
		t.Fatalf("expected runner 'claude', got %q", cfg.DefaultRunner)
	}
	if cfg.DefaultProvider != "anthropic" {
		t.Fatalf("expected provider 'anthropic', got %q", cfg.DefaultProvider)
	}
	if cfg.DefaultModel != "gpt-4" {
		t.Fatalf("expected model 'gpt-4', got %q", cfg.DefaultModel)
	}
	if cfg.DefaultThinking == nil || *cfg.DefaultThinking != 3 {
		t.Fatalf("expected thinking=3, got %v", cfg.DefaultThinking)
	}
}

func TestLoadConfig_Aliases(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	content := `
[aliases.fast]
runner = "claude"
thinking = 2
provider = "anthropic"
model = "opus"

[aliases.quick]
runner = "kimi"
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := LoadConfig(path)
	fast, ok := cfg.Aliases["fast"]
	if !ok {
		t.Fatal("expected alias 'fast'")
	}
	if fast.Runner == nil || *fast.Runner != "claude" {
		t.Fatalf("expected fast.runner=claude, got %v", fast.Runner)
	}
	if fast.Thinking == nil || *fast.Thinking != 2 {
		t.Fatalf("expected fast.thinking=2, got %v", fast.Thinking)
	}
	if fast.Provider == nil || *fast.Provider != "anthropic" {
		t.Fatalf("expected fast.provider=anthropic, got %v", fast.Provider)
	}
	if fast.Model == nil || *fast.Model != "opus" {
		t.Fatalf("expected fast.model=opus, got %v", fast.Model)
	}

	quick, ok := cfg.Aliases["quick"]
	if !ok {
		t.Fatal("expected alias 'quick'")
	}
	if quick.Runner == nil || *quick.Runner != "kimi" {
		t.Fatalf("expected quick.runner=kimi, got %v", quick.Runner)
	}
}

func TestLoadConfig_Abbreviations(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	content := `
[abbreviations]
my = "claude"
foo = "opencode"
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := LoadConfig(path)
	if cfg.Abbreviations["my"] != "claude" {
		t.Fatalf("expected abbrev my=claude, got %q", cfg.Abbreviations["my"])
	}
	if cfg.Abbreviations["foo"] != "opencode" {
		t.Fatalf("expected abbrev foo=opencode, got %q", cfg.Abbreviations["foo"])
	}
}

func TestLoadConfig_FullConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	content := `
# My config
[defaults]
runner = "claude"
provider = "anthropic"
model = "opus"
thinking = 4

[abbreviations]
cl = "claude"

[aliases.power]
runner = "claude"
thinking = 4
model = "opus"
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := LoadConfig(path)
	if cfg.DefaultRunner != "claude" {
		t.Fatalf("expected runner 'claude', got %q", cfg.DefaultRunner)
	}
	if cfg.Abbreviations["cl"] != "claude" {
		t.Fatalf("expected abbrev cl=claude, got %q", cfg.Abbreviations["cl"])
	}
	power := cfg.Aliases["power"]
	if power.Runner == nil || *power.Runner != "claude" {
		t.Fatalf("expected power.runner=claude, got %v", power.Runner)
	}
	if power.Thinking == nil || *power.Thinking != 4 {
		t.Fatalf("expected power.thinking=4, got %v", power.Thinking)
	}
}

func TestLoadConfig_EmptyPath_SearchesDefaults(t *testing.T) {
	cfg := LoadConfig("")
	if cfg == nil {
		t.Fatal("expected non-nil config")
	}
	if cfg.DefaultRunner != "oc" {
		t.Fatalf("expected default runner 'oc', got %q", cfg.DefaultRunner)
	}
}

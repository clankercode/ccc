package ccc

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"
)

func captureOutput(t *testing.T, fn func()) string {
	t.Helper()

	oldStdout := os.Stdout
	oldStderr := os.Stderr

	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}

	os.Stdout = w
	os.Stderr = w
	defer func() {
		os.Stdout = oldStdout
		os.Stderr = oldStderr
	}()

	fn()

	_ = w.Close()
	var buf bytes.Buffer
	_, _ = io.Copy(&buf, r)
	_ = r.Close()
	return buf.String()
}

func TestHelpText_UsesNameSlot(t *testing.T) {
	if !strings.Contains(HelpText, "[@name]") {
		t.Fatalf("expected help text to mention [@name], got:\n%s", HelpText)
	}
	if !strings.Contains(HelpText, "if no preset exists, treat it as an agent") {
		t.Fatalf("expected help text to describe agent fallback, got:\n%s", HelpText)
	}
	if !strings.Contains(HelpText, "codex (c/cx), roocode (rc), crush (cr)") {
		t.Fatalf("expected help text to mention codex/roocode selector names, got:\n%s", HelpText)
	}
}

func TestPrintUsage_UsesNameSlot(t *testing.T) {
	out := captureOutput(t, PrintUsage)
	if !strings.Contains(out, "usage: ccc [controls...] \"<Prompt>\"") {
		t.Fatalf("expected usage to mention [@name], got:\n%s", out)
	}
}

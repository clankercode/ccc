package ccc

import (
	"strings"
	"sync"
	"testing"
)

func TestBuildPromptSpec_Valid(t *testing.T) {
	spec, err := BuildPromptSpec("foo bar")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(spec.Argv) != 3 || spec.Argv[0] != "opencode" || spec.Argv[1] != "run" || spec.Argv[2] != "foo bar" {
		t.Fatalf("unexpected argv: %v", spec.Argv)
	}
}

func TestBuildPromptSpec_Empty(t *testing.T) {
	_, err := BuildPromptSpec("")
	if err == nil {
		t.Fatal("expected error for empty prompt")
	}
	if !strings.Contains(err.Error(), "prompt must not be empty") {
		t.Fatalf("unexpected error message: %v", err)
	}
}

func TestBuildPromptSpec_WhitespaceOnly(t *testing.T) {
	_, err := BuildPromptSpec("   \t\n  ")
	if err == nil {
		t.Fatal("expected error for whitespace-only prompt")
	}
}

func TestBuildPromptSpec_TrimsWhitespace(t *testing.T) {
	spec, err := BuildPromptSpec("  hello world  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if spec.Argv[2] != "hello world" {
		t.Fatalf("expected trimmed prompt, got: %q", spec.Argv[2])
	}
}

func TestRunner_NonexistentBinary(t *testing.T) {
	runner := NewRunner()
	result := runner.Run(CommandSpec{Argv: []string{"__nonexistent_binary_xyz__"}})
	if result.ExitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", result.ExitCode)
	}
	if !strings.Contains(result.Stderr, "failed to start") {
		t.Fatalf("expected stderr to contain 'failed to start', got: %q", result.Stderr)
	}
}

func TestRunner_ExitCodeForwarding(t *testing.T) {
	runner := NewRunner()
	result := runner.Run(CommandSpec{Argv: []string{"sh", "-c", "exit 42"}})
	if result.ExitCode != 42 {
		t.Fatalf("expected exit code 42, got %d", result.ExitCode)
	}
}

func TestRunner_StdinPassed(t *testing.T) {
	var receivedStdin string
	runner := RunWithExecutor(func(spec CommandSpec) CompletedRun {
		receivedStdin = spec.StdinText
		return CompletedRun{Argv: spec.Argv, ExitCode: 0, Stdout: "echo " + spec.StdinText}
	})
	result := runner.Run(CommandSpec{
		Argv:      []string{"echo"},
		StdinText: "hello",
	})
	if receivedStdin != "hello" {
		t.Fatalf("expected stdin 'hello', got %q", receivedStdin)
	}
	if result.Stdout != "echo hello" {
		t.Fatalf("unexpected stdout: %q", result.Stdout)
	}
}

func TestRunner_EnvOverride(t *testing.T) {
	runner := RunWithExecutor(func(spec CommandSpec) CompletedRun {
		if spec.Env["MY_VAR"] != "hello" {
			return CompletedRun{Argv: spec.Argv, ExitCode: 1, Stderr: "MY_VAR not set"}
		}
		return CompletedRun{Argv: spec.Argv, ExitCode: 0}
	})
	result := runner.Run(CommandSpec{
		Argv: []string{"env"},
		Env:  map[string]string{"MY_VAR": "hello"},
	})
	if result.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d, stderr: %q", result.ExitCode, result.Stderr)
	}
}

func TestRunner_NilArgv(t *testing.T) {
	runner := NewRunner()
	result := runner.Run(CommandSpec{Argv: nil})
	if result.ExitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", result.ExitCode)
	}
	if result.Stderr != "no command provided\n" {
		t.Fatalf("unexpected stderr: %q", result.Stderr)
	}
}

func TestStream_LineByLine(t *testing.T) {
	var mu sync.Mutex
	var events []string

	runner := NewRunner()
	result := runner.Stream(
		CommandSpec{Argv: []string{"sh", "-c", "echo line1\necho line2"}},
		func(stream string, data string) {
			mu.Lock()
			events = append(events, stream+":"+data)
			mu.Unlock()
		},
	)

	mu.Lock()
	defer mu.Unlock()
	if result.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", result.ExitCode)
	}

	foundLine1 := false
	foundLine2 := false
	for _, e := range events {
		if e == "stdout:line1" {
			foundLine1 = true
		}
		if e == "stdout:line2" {
			foundLine2 = true
		}
	}
	if !foundLine1 {
		t.Fatalf("expected stdout:line1 event, got: %v", events)
	}
	if !foundLine2 {
		t.Fatalf("expected stdout:line2 event, got: %v", events)
	}
}

func TestStream_AccumulatesOutput(t *testing.T) {
	runner := NewRunner()
	result := runner.Stream(
		CommandSpec{Argv: []string{"sh", "-c", "echo out1\necho out2\necho err1 >&2"}},
		func(stream string, data string) {},
	)

	if result.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", result.ExitCode)
	}
	if !strings.Contains(result.Stdout, "out1") || !strings.Contains(result.Stdout, "out2") {
		t.Fatalf("expected stdout to contain out1 and out2, got: %q", result.Stdout)
	}
	if !strings.Contains(result.Stderr, "err1") {
		t.Fatalf("expected stderr to contain err1, got: %q", result.Stderr)
	}
}

func TestRunner_EnvNilMeansInherit(t *testing.T) {
	runner := NewRunner()
	result := runner.Run(CommandSpec{Argv: []string{"sh", "-c", "echo ok"}})
	if result.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", result.ExitCode)
	}
	if !strings.Contains(result.Stdout, "ok") {
		t.Fatalf("expected stdout to contain 'ok', got: %q", result.Stdout)
	}
}

func TestRunner_StdoutStderr(t *testing.T) {
	runner := NewRunner()
	result := runner.Run(CommandSpec{Argv: []string{"sh", "-c", "echo hello_world"}})
	if result.ExitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", result.ExitCode)
	}
	if !strings.Contains(result.Stdout, "hello_world") {
		t.Fatalf("expected stdout to contain 'hello_world', got: %q", result.Stdout)
	}
}

func TestStream_NilArgv(t *testing.T) {
	runner := NewRunner()
	result := runner.Stream(CommandSpec{Argv: nil}, func(stream string, data string) {})
	if result.ExitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", result.ExitCode)
	}
	if result.Stderr != "no command provided\n" {
		t.Fatalf("unexpected stderr: %q", result.Stderr)
	}
}

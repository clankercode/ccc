package ccc

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type RunnerStatus struct {
	Name    string
	Alias   string
	Binary  string
	Found   bool
	Version string
}

var CanonicalRunners = []struct {
	Name  string
	Alias string
}{
	{"opencode", "oc"},
	{"claude", "cc"},
	{"kimi", "k"},
	{"codex", "c/cx"},
	{"roocode", "rc"},
	{"crush", "cr"},
}

const HelpText = `ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
`

func getVersion(binary string) string {
	cmd := exec.Command(binary, "--version")
	cmd.WaitDelay = 3e9
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	line := strings.TrimRight(string(out), "\n\r")
	if idx := strings.IndexByte(line, '\n'); idx >= 0 {
		return line[:idx]
	}
	return line
}

func RunnerChecklist() []RunnerStatus {
	statuses := make([]RunnerStatus, 0, len(CanonicalRunners))
	for _, r := range CanonicalRunners {
		info, ok := RunnerRegistry[r.Name]
		binary := r.Name
		if ok {
			binary = info.Binary
		}
		s := RunnerStatus{Name: r.Name, Alias: r.Alias, Binary: binary}
		path, err := exec.LookPath(binary)
		s.Found = err == nil && path != ""
		if s.Found {
			s.Version = getVersion(binary)
		}
		statuses = append(statuses, s)
	}
	return statuses
}

func FormatRunnerChecklist() string {
	var b strings.Builder
	b.WriteString("Runners:\n")
	for _, s := range RunnerChecklist() {
		if s.Found {
			tag := s.Version
			if tag == "" {
				tag = "found"
			}
			fmt.Fprintf(&b, "  [+] %-10s (%s)  %s\n", s.Name, s.Binary, tag)
		} else {
			fmt.Fprintf(&b, "  [-] %-10s (%s)  not found\n", s.Name, s.Binary)
		}
	}
	return b.String()
}

func PrintHelp() {
	fmt.Print(HelpText)
	fmt.Print(FormatRunnerChecklist())
}

func PrintUsage() {
	fmt.Fprintf(os.Stderr, `usage: ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
`)
	fmt.Fprint(os.Stderr, FormatRunnerChecklist())
}

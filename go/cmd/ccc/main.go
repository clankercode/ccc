package main

import (
	"fmt"
	"os"

	ccc "call-coding-clis/go"
)

func main() {
	args := os.Args[1:]
	if len(args) != 1 {
		fmt.Fprintf(os.Stderr, "usage: ccc \"<Prompt>\"\n")
		os.Exit(1)
	}

	spec, err := ccc.BuildPromptSpec(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}

	if realOpenCode := os.Getenv("CCC_REAL_OPENCODE"); realOpenCode != "" {
		spec.Argv[0] = realOpenCode
	}

	result := ccc.NewRunner().Run(spec)

	if result.Stdout != "" {
		os.Stdout.WriteString(result.Stdout)
	}
	if result.Stderr != "" {
		os.Stderr.WriteString(result.Stderr)
	}

	os.Exit(result.ExitCode)
}

package main

import (
	"fmt"
	"os"

	ccc "call-coding-clis/go"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		ccc.PrintUsage()
		os.Exit(1)
	}
	if len(args) == 1 && (args[0] == "--help" || args[0] == "-h") {
		ccc.PrintHelp()
		os.Exit(0)
	}

	parsed := ccc.ParseArgs(args)
	config := ccc.LoadConfig("")

	argv, env, warnings, err := ccc.ResolveCommand(parsed, config)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}

	for _, warning := range warnings {
		fmt.Fprintln(os.Stderr, warning)
	}

	spec := ccc.CommandSpec{
		Argv: argv,
		Env:  env,
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

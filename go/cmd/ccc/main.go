package main

import (
	"fmt"
	"os"

	ccc "call-coding-clis/go"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fmt.Fprintf(os.Stderr, "usage: ccc [runner] [+thinking] [:provider:model] [@alias] <prompt>\n")
		os.Exit(1)
	}

	parsed := ccc.ParseArgs(args)
	config := ccc.LoadConfig("")

	argv, env, err := ccc.ResolveCommand(parsed, config)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
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

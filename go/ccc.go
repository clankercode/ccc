package ccc

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
)

type CommandSpec struct {
	Argv      []string
	StdinText string
	Cwd       string
	Env       map[string]string
}

type CompletedRun struct {
	Argv     []string
	ExitCode int
	Stdout   string
	Stderr   string
}

type StreamCallback func(stream string, data string)

type Runner struct {
	executor       func(CommandSpec) CompletedRun
	streamExecutor func(CommandSpec, StreamCallback) CompletedRun
}

func NewRunner() *Runner {
	return &Runner{
		executor:       runCommand,
		streamExecutor: streamCommand,
	}
}

func RunWithExecutor(fn func(CommandSpec) CompletedRun) *Runner {
	return &Runner{executor: fn}
}

func RunWithStreamExecutor(fn func(CommandSpec, StreamCallback) CompletedRun) *Runner {
	return &Runner{streamExecutor: fn}
}

func (r *Runner) Run(spec CommandSpec) CompletedRun {
	executor := r.executor
	if executor == nil {
		executor = runCommand
	}
	return executor(spec)
}

func (r *Runner) Stream(spec CommandSpec, onEvent StreamCallback) CompletedRun {
	executor := r.streamExecutor
	if executor == nil {
		executor = streamCommand
	}
	return executor(spec, onEvent)
}

func BuildPromptSpec(prompt string) (CommandSpec, error) {
	trimmed := strings.TrimSpace(prompt)
	if trimmed == "" {
		return CommandSpec{}, fmt.Errorf("prompt must not be empty")
	}
	return CommandSpec{
		Argv: []string{"opencode", "run", trimmed},
	}, nil
}

func buildEnv(spec CommandSpec) []string {
	envMap := make(map[string]string)
	for _, entry := range os.Environ() {
		if idx := strings.IndexByte(entry, '='); idx >= 0 {
			envMap[entry[:idx]] = entry[idx+1:]
		}
	}
	for k, v := range spec.Env {
		envMap[k] = v
	}
	result := make([]string, 0, len(envMap))
	for k, v := range envMap {
		result = append(result, k+"="+v)
	}
	return result
}

func normalizeExitCode(state *os.ProcessState) int {
	if code := state.ExitCode(); code >= 0 {
		return code
	}
	return 1
}

func runCommand(spec CommandSpec) CompletedRun {
	if len(spec.Argv) == 0 {
		return CompletedRun{ExitCode: 1, Stderr: "no command provided\n"}
	}

	cmd := exec.Command(spec.Argv[0], spec.Argv[1:]...)
	if spec.Cwd != "" {
		cmd.Dir = spec.Cwd
	}
	if len(spec.Env) > 0 {
		cmd.Env = buildEnv(spec)
	}
	if spec.StdinText != "" {
		cmd.Stdin = strings.NewReader(spec.StdinText)
	}

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	err := cmd.Run()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return CompletedRun{
				Argv:     spec.Argv,
				ExitCode: normalizeExitCode(exitErr.ProcessState),
				Stdout:   stdoutBuf.String(),
				Stderr:   stderrBuf.String(),
			}
		}
		prog := spec.Argv[0]
		if prog == "" {
			prog = "(unknown)"
		}
		return CompletedRun{
			Argv:     spec.Argv,
			ExitCode: 1,
			Stderr:   fmt.Sprintf("failed to start %s: %s\n", prog, err),
		}
	}

	return CompletedRun{
		Argv:     spec.Argv,
		ExitCode: 0,
		Stdout:   stdoutBuf.String(),
		Stderr:   stderrBuf.String(),
	}
}

func streamCommand(spec CommandSpec, onEvent StreamCallback) CompletedRun {
	if len(spec.Argv) == 0 {
		return CompletedRun{ExitCode: 1, Stderr: "no command provided\n"}
	}

	cmd := exec.Command(spec.Argv[0], spec.Argv[1:]...)
	if spec.Cwd != "" {
		cmd.Dir = spec.Cwd
	}
	if len(spec.Env) > 0 {
		cmd.Env = buildEnv(spec)
	}

	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		return startupFailure(spec.Argv, err)
	}

	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		return startupFailure(spec.Argv, err)
	}

	var stdinWriter io.WriteCloser
	if spec.StdinText != "" {
		stdinWriter, err = cmd.StdinPipe()
		if err != nil {
			return startupFailure(spec.Argv, err)
		}
	}

	if err := cmd.Start(); err != nil {
		return startupFailure(spec.Argv, err)
	}

	var wg sync.WaitGroup
	wg.Add(2)

	var stdoutBuf, stderrBuf strings.Builder

	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stdoutPipe)
		for scanner.Scan() {
			line := scanner.Text()
			stdoutBuf.WriteString(line)
			stdoutBuf.WriteByte('\n')
			if onEvent != nil {
				onEvent("stdout", line)
			}
		}
		if serr := scanner.Err(); serr != nil {
			stdoutBuf.WriteString(fmt.Sprintf("[scanner error: %s]", serr))
		}
	}()

	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stderrPipe)
		for scanner.Scan() {
			line := scanner.Text()
			stderrBuf.WriteString(line)
			stderrBuf.WriteByte('\n')
			if onEvent != nil {
				onEvent("stderr", line)
			}
		}
		if serr := scanner.Err(); serr != nil {
			stderrBuf.WriteString(fmt.Sprintf("[scanner error: %s]", serr))
		}
	}()

	if spec.StdinText != "" {
		go func() {
			io.WriteString(stdinWriter, spec.StdinText)
			stdinWriter.Close()
		}()
	}

	err = cmd.Wait()
	wg.Wait()

	var exitCode int
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			exitCode = normalizeExitCode(exitErr.ProcessState)
		} else {
			exitCode = 1
		}
	}

	return CompletedRun{
		Argv:     spec.Argv,
		ExitCode: exitCode,
		Stdout:   stdoutBuf.String(),
		Stderr:   stderrBuf.String(),
	}
}

func startupFailure(argv []string, err error) CompletedRun {
	prog := "(unknown)"
	if len(argv) > 0 && argv[0] != "" {
		prog = argv[0]
	}
	return CompletedRun{
		Argv:     argv,
		ExitCode: 1,
		Stderr:   fmt.Sprintf("failed to start %s: %s\n", prog, err),
	}
}

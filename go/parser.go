package ccc

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type RunnerInfo struct {
	Binary        string
	ExtraArgs     []string
	ThinkingFlags map[int][]string
	ProviderFlag  string
	ModelFlag     string
	AgentFlag     string
}

type ParsedArgs struct {
	Runner   *string
	Thinking *int
	Provider *string
	Model    *string
	Alias    *string
	Prompt   string
}

type AliasDef struct {
	Runner   *string
	Thinking *int
	Provider *string
	Model    *string
	Agent    *string
}

type CccConfig struct {
	DefaultRunner   string
	DefaultProvider string
	DefaultModel    string
	DefaultThinking *int
	Aliases         map[string]AliasDef
	Abbreviations   map[string]string
}

var RunnerRegistry map[string]RunnerInfo

var (
	runnerSelectorRE *regexp.Regexp
	thinkingRE       *regexp.Regexp
	providerModelRE  *regexp.Regexp
	modelRE          *regexp.Regexp
	aliasRE          *regexp.Regexp
)

func init() {
	RunnerRegistry = map[string]RunnerInfo{
		"opencode": {
			Binary:    "opencode",
			ExtraArgs: []string{"run"},
			AgentFlag: "--agent",
		},
		"claude": {
			Binary: "claude",
			ThinkingFlags: map[int][]string{
				0: {"--no-thinking"},
				1: {"--thinking", "low"},
				2: {"--thinking", "medium"},
				3: {"--thinking", "high"},
				4: {"--thinking", "max"},
			},
			ModelFlag: "--model",
			AgentFlag: "--agent",
		},
		"kimi": {
			Binary: "kimi",
			ThinkingFlags: map[int][]string{
				0: {"--no-think"},
				1: {"--think", "low"},
				2: {"--think", "medium"},
				3: {"--think", "high"},
				4: {"--think", "max"},
			},
			ModelFlag: "--model",
			AgentFlag: "--agent",
		},
		"codex": {
			Binary:    "codex",
			ModelFlag: "--model",
		},
		"roocode": {
			Binary:    "roocode",
			ModelFlag: "--model",
		},
		"crush": {
			Binary: "crush",
		},
	}
	RunnerRegistry["oc"] = RunnerRegistry["opencode"]
	RunnerRegistry["cc"] = RunnerRegistry["claude"]
	RunnerRegistry["c"] = RunnerRegistry["codex"]
	RunnerRegistry["cx"] = RunnerRegistry["codex"]
	RunnerRegistry["k"] = RunnerRegistry["kimi"]
	RunnerRegistry["rc"] = RunnerRegistry["roocode"]
	RunnerRegistry["cr"] = RunnerRegistry["crush"]

	runnerSelectorRE = regexp.MustCompile(`(?i)^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$`)
	thinkingRE = regexp.MustCompile(`^\+([0-4])$`)
	providerModelRE = regexp.MustCompile(`^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$`)
	modelRE = regexp.MustCompile(`^:([a-zA-Z0-9._-]+)$`)
	aliasRE = regexp.MustCompile(`^@([a-zA-Z0-9_-]+)$`)
}

func ptrStr(s string) *string { return &s }
func ptrInt(i int) *int       { return &i }

func ParseArgs(argv []string) ParsedArgs {
	var parsed ParsedArgs
	var positional []string

	for _, token := range argv {
		if runnerSelectorRE.MatchString(token) && parsed.Runner == nil && len(positional) == 0 {
			lower := strings.ToLower(token)
			parsed.Runner = &lower
		} else if m := thinkingRE.FindStringSubmatch(token); m != nil && len(positional) == 0 {
			val, _ := strconv.Atoi(m[1])
			parsed.Thinking = ptrInt(val)
		} else if m := providerModelRE.FindStringSubmatch(token); m != nil && len(positional) == 0 {
			parsed.Provider = &m[1]
			parsed.Model = &m[2]
		} else if m := modelRE.FindStringSubmatch(token); m != nil && len(positional) == 0 {
			parsed.Model = &m[1]
		} else if m := aliasRE.FindStringSubmatch(token); m != nil && parsed.Alias == nil && len(positional) == 0 {
			parsed.Alias = &m[1]
		} else {
			positional = append(positional, token)
		}
	}

	parsed.Prompt = strings.Join(positional, " ")
	return parsed
}

func resolveRunnerName(name *string, config *CccConfig) string {
	if name == nil {
		return config.DefaultRunner
	}
	if abbrev, ok := config.Abbreviations[*name]; ok {
		return abbrev
	}
	return *name
}

func ResolveCommand(parsed ParsedArgs, config *CccConfig) ([]string, map[string]string, []string, error) {
	if config == nil {
		config = DefaultConfig()
	}

	runnerName := resolveRunnerName(parsed.Runner, config)
	info, ok := RunnerRegistry[runnerName]
	if !ok {
		info, ok = RunnerRegistry[config.DefaultRunner]
		if !ok {
			info = RunnerRegistry["opencode"]
		}
	}

	var warnings []string
	var aliasDef *AliasDef
	if parsed.Alias != nil {
		if ad, exists := config.Aliases[*parsed.Alias]; exists {
			aliasDef = &ad
		}
	}

	var requestedAgent *string
	if parsed.Alias != nil && aliasDef == nil {
		requestedAgent = parsed.Alias
	}

	if aliasDef != nil && aliasDef.Runner != nil && parsed.Runner == nil {
		effectiveName := resolveRunnerName(aliasDef.Runner, config)
		if ri, found := RunnerRegistry[effectiveName]; found {
			info = ri
		}
	}

	argv := make([]string, 0, 1+len(info.ExtraArgs))
	argv = append(argv, info.Binary)
	argv = append(argv, info.ExtraArgs...)

	effectiveThinking := parsed.Thinking
	if effectiveThinking == nil && aliasDef != nil && aliasDef.Thinking != nil {
		effectiveThinking = aliasDef.Thinking
	}
	if effectiveThinking == nil {
		effectiveThinking = config.DefaultThinking
	}
	if effectiveThinking != nil {
		if flags, exists := info.ThinkingFlags[*effectiveThinking]; exists {
			argv = append(argv, flags...)
		}
	}

	effectiveProvider := parsed.Provider
	if effectiveProvider == nil && aliasDef != nil && aliasDef.Provider != nil && *aliasDef.Provider != "" {
		effectiveProvider = aliasDef.Provider
	}
	if effectiveProvider == nil && config.DefaultProvider != "" {
		effectiveProvider = ptrStr(config.DefaultProvider)
	}

	effectiveModel := parsed.Model
	if effectiveModel == nil && aliasDef != nil && aliasDef.Model != nil && *aliasDef.Model != "" {
		effectiveModel = aliasDef.Model
	}
	if effectiveModel == nil && config.DefaultModel != "" {
		effectiveModel = ptrStr(config.DefaultModel)
	}

	if effectiveModel != nil && *effectiveModel != "" && info.ModelFlag != "" {
		argv = append(argv, info.ModelFlag, *effectiveModel)
	}

	effectiveAgent := requestedAgent
	if aliasDef != nil && aliasDef.Agent != nil && *aliasDef.Agent != "" {
		effectiveAgent = aliasDef.Agent
	}
	if effectiveAgent != nil && *effectiveAgent != "" {
		if info.AgentFlag != "" {
			argv = append(argv, info.AgentFlag, *effectiveAgent)
		} else {
			warnings = append(warnings, fmt.Sprintf("warning: runner %q does not support agents; ignoring @%s", info.Binary, *effectiveAgent))
		}
	}

	envOverrides := map[string]string{}
	if effectiveProvider != nil && *effectiveProvider != "" {
		envOverrides["CCC_PROVIDER"] = *effectiveProvider
	}

	prompt := strings.TrimSpace(parsed.Prompt)
	if prompt == "" {
		return nil, nil, nil, fmt.Errorf("prompt must not be empty")
	}

	argv = append(argv, prompt)
	return argv, envOverrides, warnings, nil
}

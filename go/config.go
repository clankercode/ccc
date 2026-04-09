package ccc

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func DefaultConfig() *CccConfig {
	return &CccConfig{
		DefaultRunner: "oc",
		Aliases:       map[string]AliasDef{},
		Abbreviations: map[string]string{},
	}
}

func LoadConfig(path string) *CccConfig {
	if path != "" {
		return loadFromFile(path)
	}

	if xdg := os.Getenv("XDG_CONFIG_HOME"); xdg != "" {
		candidate := filepath.Join(xdg, "ccc", "config.toml")
		if fileExists(candidate) {
			return loadFromFile(candidate)
		}
	}

	home, err := os.UserHomeDir()
	if err == nil {
		candidate := filepath.Join(home, ".config", "ccc", "config.toml")
		if fileExists(candidate) {
			return loadFromFile(candidate)
		}
	}

	return DefaultConfig()
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func loadFromFile(path string) *CccConfig {
	config := DefaultConfig()

	data, err := os.ReadFile(path)
	if err != nil {
		return config
	}

	lines := strings.Split(string(data), "\n")
	section := ""
	subsection := ""

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			header := strings.TrimSpace(line[1 : len(line)-1])
			parts := strings.SplitN(header, ".", 2)
			section = parts[0]
			subsection = ""
			if len(parts) == 2 {
				subsection = parts[1]
			}
			if section == "aliases" && subsection != "" {
				if _, ok := config.Aliases[subsection]; !ok {
					config.Aliases[subsection] = AliasDef{}
				}
			}
			continue
		}

		eqIdx := strings.Index(line, "=")
		if eqIdx < 0 {
			continue
		}
		key := strings.TrimSpace(line[:eqIdx])
		val := strings.TrimSpace(line[eqIdx+1:])

		switch section {
		case "defaults":
			switch key {
			case "runner":
				config.DefaultRunner = unquote(val)
			case "provider":
				config.DefaultProvider = unquote(val)
			case "model":
				config.DefaultModel = unquote(val)
			case "thinking":
				if n, err := strconv.Atoi(val); err == nil {
					config.DefaultThinking = ptrInt(n)
				}
			}
		case "abbreviations":
			config.Abbreviations[key] = unquote(val)
		case "aliases":
			if subsection != "" {
				alias := config.Aliases[subsection]
				switch key {
				case "runner":
					v := unquote(val)
					alias.Runner = &v
				case "thinking":
					if n, err := strconv.Atoi(val); err == nil {
						alias.Thinking = ptrInt(n)
					}
				case "provider":
					v := unquote(val)
					alias.Provider = &v
				case "model":
					v := unquote(val)
					alias.Model = &v
				case "agent":
					v := unquote(val)
					alias.Agent = &v
				}
				config.Aliases[subsection] = alias
			}
		}
	}

	return config
}

func unquote(s string) string {
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}
	return s
}

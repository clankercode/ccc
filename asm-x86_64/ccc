#!/bin/sh
set -eu

usage() {
  cat >&2 <<'EOF'
usage: ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
EOF
}

help_text() {
  cat <<'EOF'
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
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

Note:
  This x86-64 ASM shim currently implements prompt-only execution, config-driven default runner selection, and @name preset/agent fallback.
  Runner/thinking/provider CLI slots are not parsed here.
EOF
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

find_config_path() {
  if [ -n "${CCC_CONFIG:-}" ] && [ -f "$CCC_CONFIG" ] && [ -s "$CCC_CONFIG" ]; then
    printf '%s' "$CCC_CONFIG"
    return 0
  fi

  for base in "${XDG_CONFIG_HOME:-}" "${HOME:-}"; do
    if [ -n "$base" ]; then
      for suffix in "/ccc/config.toml" "/ccc/config"; do
        path="$base$suffix"
        if [ -f "$path" ] && [ -s "$path" ]; then
          printf '%s' "$path"
          return 0
        fi
      done
    fi
  done
  return 1
}

toml_read_value() {
  path=$1
  wanted_section=$2
  wanted_key=$3

  awk -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    BEGIN {
      found = 0
    }

    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || substr(line, 1, 1) == "#") next

      if (line ~ /^\[/) {
        section = line
        sub(/^\[/, "", section)
        sub(/\][[:space:]]*$/, "", section)
        next
      }

      if (section != wanted_section) next

      pos = index(line, "=")
      if (pos == 0) next

      lhs = trim(substr(line, 1, pos - 1))
      rhs = trim(substr(line, pos + 1))
      sub(/^"/, "", rhs)
      sub(/"$/, "", rhs)

      if (lhs == wanted_key) {
        print rhs
        found = 1
        exit 0
      }
    }

    END {
      exit found ? 0 : 1
    }
  ' "$path"
}

toml_has_section() {
  path=$1
  wanted_section=$2

  awk -v wanted_section="$wanted_section" '
    BEGIN {
      found = 0
    }

    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || substr(line, 1, 1) == "#") next

      if (line ~ /^\[/) {
        section = line
        sub(/^\[/, "", section)
        sub(/\][[:space:]]*$/, "", section)
        if (section == wanted_section) {
          found = 1
          exit 0
        }
      }
    }

    END {
      exit found ? 0 : 1
    }
  ' "$path"
}

read_default_runner() {
  path=$1
  value=""
  if [ -n "$path" ]; then
    if value=$(toml_read_value "$path" defaults runner 2>/dev/null); then
      printf '%s' "$value"
      return 0
    fi
    if value=$(toml_read_value "$path" "" default_runner 2>/dev/null); then
      printf '%s' "$value"
      return 0
    fi
  fi
  return 1
}

read_alias_field() {
  path=$1
  alias_name=$2
  wanted_key=$3

  if [ -z "$path" ]; then
    return 1
  fi

  if toml_has_section "$path" "aliases.$alias_name"; then
    toml_read_value "$path" "aliases.$alias_name" "$wanted_key"
    return
  fi

  if toml_has_section "$path" "alias.$alias_name"; then
    toml_read_value "$path" "alias.$alias_name" "$wanted_key"
    return
  fi

  return 1
}

run_runner() {
  runner=$1
  agent=$2
  prompt=$3

  case "$runner" in
    opencode|oc)
      bin=${CCC_REAL_OPENCODE:-opencode}
      if ! command -v "$bin" >/dev/null 2>&1; then
        printf 'ccc: failed to start %s\n' "$bin" >&2
        exit 127
      fi
      if [ -n "$agent" ]; then
        exec "$bin" run --agent "$agent" "$prompt"
      fi
      exec "$bin" run "$prompt"
      ;;
    claude|cc|c)
      if [ -n "$agent" ]; then
        exec claude --agent "$agent" "$prompt"
      fi
      exec claude "$prompt"
      ;;
    kimi|k)
      if [ -n "$agent" ]; then
        exec kimi --agent "$agent" "$prompt"
      fi
      exec kimi "$prompt"
      ;;
    codex|rc)
      if [ -n "$agent" ]; then
        printf 'warning: runner "%s" does not support agents; ignoring @%s\n' "$runner" "$agent" >&2
      fi
      exec codex "$prompt"
      ;;
    crush|cr)
      if [ -n "$agent" ]; then
        printf 'warning: runner "%s" does not support agents; ignoring @%s\n' "$runner" "$agent" >&2
      fi
      exec crush "$prompt"
      ;;
    *)
      if [ -n "$agent" ]; then
        printf 'warning: runner "%s" does not support agents; ignoring @%s\n' "$runner" "$agent" >&2
      fi
      exec "$runner" "$prompt"
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

if [ "$#" -eq 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
  help_text
  exit 0
fi

config_path=""
if found_config=$(find_config_path 2>/dev/null); then
  config_path=$found_config
fi

runner_default=opencode
if [ -n "$config_path" ]; then
  if value=$(read_default_runner "$config_path" 2>/dev/null); then
    runner_default=$value
  fi
fi

if [ "$#" -eq 1 ]; then
  prompt=$(trim "$1")
  if [ "$prompt" = "" ]; then
    printf 'prompt must not be empty\n' >&2
    exit 1
  fi
  run_runner "$runner_default" "" "$prompt"
fi

if [ "$#" -eq 2 ] && [ "${1#@}" != "$1" ]; then
  alias_name=${1#@}
  prompt=$(trim "$2")
  if [ "$prompt" = "" ]; then
    printf 'prompt must not be empty\n' >&2
    exit 1
  fi

  runner=$runner_default
  agent=""
  if [ -n "$config_path" ] && (toml_has_section "$config_path" "aliases.$alias_name" || toml_has_section "$config_path" "alias.$alias_name"); then
    if value=$(read_alias_field "$config_path" "$alias_name" runner 2>/dev/null); then
      if [ "$value" != "" ]; then
        runner=$value
      fi
    fi
    if value=$(read_alias_field "$config_path" "$alias_name" agent 2>/dev/null); then
      if [ "$value" != "" ]; then
        agent=$value
      fi
    fi
  else
    agent=$alias_name
  fi

  run_runner "$runner" "$agent" "$prompt"
fi

usage
exit 1

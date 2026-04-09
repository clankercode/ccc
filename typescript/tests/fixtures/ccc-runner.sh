#!/bin/sh
if [ "$1" = "run" ]; then
  shift
fi
prompt="${1:-}"

printf 'ccc-stdout:%s\n' "$prompt"
printf 'ccc-stderr:%s\n' "$prompt" >&2

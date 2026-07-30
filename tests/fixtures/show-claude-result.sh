#!/usr/bin/env bash

set -e

claude_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '● Implemented the requested public behavior.' \
  '' \
  '● Tests pass at the isolated tmux seam.' \
  '' \
  '❯ Try "add another test"' \
  '' \
  '  ? for shortcuts'

exec "$claude_command" -c 'while IFS= read -r _line; do :; done'

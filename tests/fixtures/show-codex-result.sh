#!/usr/bin/env bash

set -e

codex_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '• Implemented the requested public behavior.' \
  '' \
  '• Tests pass at the isolated tmux seam.' \
  '' \
  '› Ask Codex to do anything' \
  '' \
  '  gpt-5 · 96% left'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

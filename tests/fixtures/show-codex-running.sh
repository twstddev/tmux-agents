#!/usr/bin/env bash

set -e

codex_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '╭────────────────────────────────────────╮' \
  '│ >_ OpenAI Codex                       │' \
  '╰────────────────────────────────────────╯' \
  '' \
  '• The Agent is working through the request.' \
  '' \
  '• Working (4s • esc to interrupt)' \
  '' \
  '' \
  '› Improve documentation in @filename' \
  '' \
  '  gpt-5 · 98% left'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

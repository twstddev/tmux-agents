#!/usr/bin/env bash

set -e

codex_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '╭────────────────────────────────────────╮' \
  '│ >_ OpenAI Codex                       │' \
  '╰────────────────────────────────────────╯' \
  '' \
  '› Ask Codex to do anything' \
  '' \
  '  gpt-5 · 100% left'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

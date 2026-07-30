#!/usr/bin/env bash

set -e

claude_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '╭── Claude Code ──╮' \
  '│ Welcome back! │' \
  '╰───────────────╯' \
  '' \
  '❯ Try "explain this project"' \
  '' \
  '  ? for shortcuts'

exec "$claude_command" -c 'while IFS= read -r _line; do :; done'

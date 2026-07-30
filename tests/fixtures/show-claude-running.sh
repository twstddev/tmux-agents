#!/usr/bin/env bash

set -e

claude_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  '╭── Claude Code ──╮' \
  '│ Welcome back! │' \
  '╰───────────────╯' \
  '' \
  '❯ Check the public behavior' \
  '' \
  '✻ Crafting… (4s · esc to interrupt)' \
  '' \
  '  ? for shortcuts'

exec "$claude_command" -c 'while IFS= read -r _line; do :; done'

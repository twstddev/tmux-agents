#!/usr/bin/env bash

set -e

claude_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  'Claude wants to edit a file' \
  '' \
  'Do you want to proceed?' \
  '' \
  '❯ 1. Yes' \
  '  2. No' \
  '' \
  '  Esc to cancel'

exec "$claude_command" -c 'while IFS= read -r _line; do :; done'

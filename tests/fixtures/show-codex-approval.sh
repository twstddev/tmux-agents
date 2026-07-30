#!/usr/bin/env bash

set -e

codex_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  'Would you like to run the following command?' \
  '' \
  '  git status --short' \
  '' \
  '› 1. Yes, proceed' \
  '  2. No, and tell Codex what to do differently' \
  '' \
  '  Press enter to confirm or esc to cancel'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

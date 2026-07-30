#!/usr/bin/env bash

set -e

codex_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  'Question 1/1' \
  '' \
  'Which interface should the test exercise?' \
  '' \
  '› 1. Public plugin behavior' \
  '  2. Private shell functions' \
  '' \
  '  Press enter to submit or esc to cancel'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

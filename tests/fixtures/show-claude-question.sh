#!/usr/bin/env bash

set -e

claude_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  'Question 1/1' \
  '' \
  'Which interface should the test exercise?' \
  '' \
  '❯ Public plugin behavior' \
  '  Private shell functions' \
  '' \
  '  Enter to select · Esc to cancel'

exec "$claude_command" -c 'while IFS= read -r _line; do :; done'

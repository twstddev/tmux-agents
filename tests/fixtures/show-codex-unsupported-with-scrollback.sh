#!/usr/bin/env bash

set -e

codex_command=$1
scrollback_marker=$2

printf '%s\n' "$scrollback_marker"
printf '%s\n' '• Working (1s • esc to interrupt)'
line_number=1
while [ "$line_number" -le 24 ]; do
  printf '\n'
  line_number=$((line_number + 1))
done
printf '%s\n' 'Visible output has no supported evidence.'

exec "$codex_command" -c 'while IFS= read -r _line; do :; done'

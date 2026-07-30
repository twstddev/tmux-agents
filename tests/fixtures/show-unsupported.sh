#!/usr/bin/env bash

set -e

agent_command=$1

printf '\033[2J\033[H'
printf '%s\n' \
  'Agent output in an unsupported layout' \
  '' \
  'A transcript mentions esc to interrupt.' \
  'No recognized prompt or working footer is visible.'

exec "$agent_command" -c 'while IFS= read -r _line; do :; done'

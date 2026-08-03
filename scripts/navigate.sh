#!/bin/sh

set -eu

invoking_client=${1-}
target_pane=$(tmux list-panes -a -F \
  '#{pane_id}|#{pane_dead}|#{@tmux_agents_attention}' |
  awk -F '|' '$2 == "0" && $3 != "" { print $3 "|" $1 }' |
  sort -n -t '|' -k1,1 -k2,2 |
  sed -n '1s/^[^|]*|//p')

if [ -z "$target_pane" ]; then
  if [ -n "$invoking_client" ]; then
    tmux display-message -c "$invoking_client" 'No agents need attention'
  else
    tmux display-message 'No agents need attention'
  fi
  exit 0
fi

if [ -n "$invoking_client" ]; then
  tmux switch-client -c "$invoking_client" -t "$target_pane" \
    2>/dev/null || true
else
  tmux switch-client -t "$target_pane" 2>/dev/null || true
fi

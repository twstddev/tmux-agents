#!/bin/sh

set -eu

invoking_client=${1-}
queue=${2-attention}

case "$queue" in
  attention)
    marker_format='#{@tmux_agents_attention}'
    empty_message='No agents need attention'
    ;;
  finished)
    marker_format='#{@tmux_agents_finished}'
    empty_message='No agents have finished'
    ;;
  *) exit 0 ;;
esac

target_pane=$(tmux list-panes -a -F \
  "#{pane_id}|#{pane_dead}|$marker_format" |
  awk -F '|' '$2 == "0" && $3 != "" { print $3 "|" $1 }' |
  LC_ALL=C sort -t '|' -k1,1n -k2,2 |
  sed -n '1s/^[^|]*|//p')

if [ -z "$target_pane" ]; then
  if [ -n "$invoking_client" ]; then
    tmux display-message -c "$invoking_client" "$empty_message"
  else
    tmux display-message "$empty_message"
  fi
  exit 0
fi

if [ -n "$invoking_client" ]; then
  tmux switch-client -c "$invoking_client" -t "$target_pane" \
    2>/dev/null || true
else
  tmux switch-client -t "$target_pane" 2>/dev/null || true
fi

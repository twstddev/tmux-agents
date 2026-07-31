#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
client_name=$1

"$plugin_root/scripts/reconcile.sh"
"$plugin_root/scripts/scan.sh"

target_pane=
while IFS=$'\t' read -r _state_since pane_id; do
  target_pane=$pane_id
  break
done < <(
  while IFS= read -r pane_id; do
    pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
    [ "$pane_state" = 'attention' ] || continue

    pane_since=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_since')
    case "$pane_since" in
    '' | *[!0-9]*) pane_since=0 ;;
    esac

    printf '%020d\t%s\n' "$pane_since" "$pane_id"
  done < <(tmux list-panes -a -F '#{pane_id}') |
    LC_ALL=C sort -t $'\t' -k1,1n -k2,2
)

if [ -z "$target_pane" ]; then
  tmux display-message -c "$client_name" 'tmux-agents: no Agent needs attention'
  exit 0
fi

"$plugin_root/scripts/navigate.sh" "$client_name" "$target_pane"

#!/bin/sh

set -eu

plugin_path=$(cd -- "$(dirname -- "$0")/.." && pwd)
operation=${1-}

case "$operation" in
  mark|clear) ;;
  *) exit 0 ;;
esac

target_pane=${TMUX_PANE-}
[ -n "$target_pane" ] || exit 0

if ! tmux display-message -p -t "$target_pane" '#{pane_id}' \
  >/dev/null 2>&1; then
  exit 0
fi

case "$operation" in
  mark)
    tmux set-option -pq -t "$target_pane" '@tmux_agents_attention' "$(date +%s)"
    ;;
  clear)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_attention' 2>/dev/null || true
    ;;
esac

"$plugin_path/scripts/status.sh"

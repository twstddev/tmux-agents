#!/bin/sh

set -eu

plugin_path=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
operation=${1-}

case "$operation" in
  mark|clear|complete|view) ;;
  *) exit 0 ;;
esac

target_pane=${2-${TMUX_PANE-}}
[ -n "$target_pane" ] || exit 0

if ! tmux display-message -p -t "$target_pane" '#{pane_id}' \
  >/dev/null 2>&1; then
  exit 0
fi

case "$operation" in
  mark)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_finished' \
      2>/dev/null || true
    tmux set-option -pq -t "$target_pane" '@tmux_agents_attention' "$(date +%s)"
    ;;
  clear)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_attention' 2>/dev/null || true
    tmux set-option -puq -t "$target_pane" '@tmux_agents_finished' 2>/dev/null || true
    ;;
  complete)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_attention' 2>/dev/null || true
    if tmux list-clients -F '#{pane_id}' |
      awk -v target="$target_pane" '$0 == target { found = 1 } END { exit !found }'; then
      tmux set-option -puq -t "$target_pane" '@tmux_agents_finished' 2>/dev/null || true
    elif [ -z "$(tmux show-options -pqv -t "$target_pane" \
      '@tmux_agents_finished')" ]; then
      tmux set-option -pq -t "$target_pane" '@tmux_agents_finished' "$(date +%s)"
    fi
    ;;
  view)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_finished' 2>/dev/null || true
    ;;
esac

"$plugin_path/scripts/status.sh"

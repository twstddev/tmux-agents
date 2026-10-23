#!/bin/sh

set -eu

plugin_path=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
operation=${1-}

case "$operation" in
  mark|clear|complete|view|start|end) ;;
  *) exit 0 ;;
esac

target_pane=${2-${TMUX_PANE-}}
[ -n "$target_pane" ] || exit 0

if ! tmux display-message -p -t "$target_pane" '#{pane_id}' \
  >/dev/null 2>&1; then
  exit 0
fi

case "$operation" in
  start|end)
    # JSON is optional for attention tracking. jq is only needed for resume IDs.
    case "${3-}" in
      codex) resume_prefix='codex resume' ;;
      claude) resume_prefix='claude --resume' ;;
      *) exit 0 ;;
    esac
    if command -v jq >/dev/null 2>&1; then
      session_id=$(jq -ser 'select(length == 1) | .[0].session_id |
        select(type == "string") |
        select(test("^[A-Za-z0-9_][A-Za-z0-9_-]*$"))' 2>/dev/null || true)
      if [ -n "$session_id" ]; then
        resume_command="$resume_prefix $session_id"
        if [ "$operation" = end ]; then
          recorded_resume=$(tmux show-options -pqv -t "$target_pane" \
            '@tmux_agents_resume_command')
          if [ "$recorded_resume" = "$resume_command" ]; then
            tmux set-option -puq -t "$target_pane" '@tmux_agents_resume_command'
          elif [ -n "$recorded_resume" ]; then
            # An older session can finish after a new one starts in this pane.
            exit 0
          fi
        else
          tmux set-option -pq -t "$target_pane" \
            '@tmux_agents_resume_command' "$resume_command"
        fi
      fi
    fi
    ;;
esac

case "$operation" in
  mark)
    tmux set-option -puq -t "$target_pane" '@tmux_agents_finished' \
      2>/dev/null || true
    tmux set-option -pq -t "$target_pane" '@tmux_agents_attention' "$(date +%s)"
    ;;
  clear|start|end)
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

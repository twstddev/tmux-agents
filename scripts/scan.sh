#!/usr/bin/env bash

set -e

selected_pane=$1
attention_count=0
running_count=0
unknown_count=0
stale_count=0
total_count=0

clear_agent_state() {
  pane_id_to_clear=$1

  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_type' 2>/dev/null || true
  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_state' 2>/dev/null || true
}

set_agent_state() {
  pane_id_to_set=$1
  agent_type_to_set=$2
  state_to_set=$3

  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_type' "$agent_type_to_set"
  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_state' "$state_to_set"
  pane_state=$state_to_set
}

screen_shows_running() {
  agent_type_to_check=$1

  awk -v agent_type="$agent_type_to_check" '
    agent_type == "codex" &&
      $0 ~ "^[[:space:]]*•[[:space:]]+Working[[:space:]]*\\(" &&
      /esc to interrupt/ {
        running_line = NR
        nonblank_lines_after_running = 0
      }
    agent_type == "claude" &&
      $0 ~ "^[[:space:]]*(✻|✽|✶|✢|⚗)[[:space:]]+" &&
      /esc to interrupt/ {
        running_line = NR
        nonblank_lines_after_running = 0
      }
    running_line && NR > running_line && /[^[:space:]]/ {
      nonblank_lines_after_running++
    }
    END {
      if (!running_line || nonblank_lines_after_running > 3) {
        exit 1
      }
    }
  '
}

while IFS='|' read -r pane_id pane_command; do
  pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')

  case "$pane_command" in
    codex) prompt_marker='›' ;;
    claude) prompt_marker='❯' ;;
    *)
      clear_agent_state "$pane_id"
      continue
      ;;
  esac

  current_screen=$(tmux capture-pane -p -t "$pane_id")
  if printf '%s\n' "$current_screen" | screen_shows_running "$pane_command"; then
    set_agent_state "$pane_id" "$pane_command" 'running'
  elif printf '%s\n' "$current_screen" | awk -v prompt_marker="$prompt_marker" '
    $0 ~ "^[[:space:]]*" prompt_marker { prompt_line = NR }
    /[^[:space:]]/ { last_nonblank_line = NR }
    END {
      if (!prompt_line || last_nonblank_line - prompt_line > 3) {
        exit 1
      }
    }
  '; then
    if [ "$pane_id" = "$selected_pane" ]; then
      set_agent_state "$pane_id" "$pane_command" 'stale'
    elif [ -z "$pane_state" ]; then
      set_agent_state "$pane_id" "$pane_command" 'unknown'
    else
      tmux set-option -pq -t "$pane_id" '@tmux_agents_type' "$pane_command"
    fi
  else
    set_agent_state "$pane_id" "$pane_command" 'unknown'
  fi

  if [ "$pane_state" = 'running' ]; then
    running_count=$((running_count + 1))
    total_count=$((total_count + 1))
  fi

  if [ "$pane_state" = 'unknown' ]; then
    unknown_count=$((unknown_count + 1))
    total_count=$((total_count + 1))
  fi

  if [ "$pane_state" = 'stale' ]; then
    stale_count=$((stale_count + 1))
    total_count=$((total_count + 1))
  fi
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_current_command}')

tmux set-option -gq '@tmux_agents_count_attention' "$attention_count"
tmux set-option -gq '@tmux_agents_count_running' "$running_count"
tmux set-option -gq '@tmux_agents_count_unknown' "$unknown_count"
tmux set-option -gq '@tmux_agents_count_stale' "$stale_count"
tmux set-option -gq '@tmux_agents_count_total' "$total_count"

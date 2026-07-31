#!/usr/bin/env bash

# Shared pane-state boundary. Callers supply event evidence, never screen text.

state_clear_attention_event() {
  state_pane_id=$1

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_attention_evidence' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_attention_signature' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_acknowledged_signature' 2>/dev/null || true
}

state_remove_agent() {
  state_pane_id=$1

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_type' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_identity' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state_source' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_evidence' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state_since' 2>/dev/null || true
  state_clear_attention_event "$state_pane_id"
}

state_starts_new_wait() {
  previous_state=$1
  previous_attention_signature=$2
  previous_acknowledged_signature=$3
  next_state=$4
  next_attention_signature=$5
  next_acknowledged_signature=$6

  if [ "$previous_state" != "$next_state" ]; then
    return 0
  fi
  if [ "$next_state" != 'attention' ] || [ -z "$next_attention_signature" ]; then
    return 1
  fi
  if [ "$previous_attention_signature" != "$next_attention_signature" ]; then
    return 0
  fi

  [ -z "$next_acknowledged_signature" ] &&
    [ "$previous_acknowledged_signature" = "$next_attention_signature" ]
}

state_transition_agent() {
  state_pane_id=$1
  state_agent_type=$2
  state_next=$3
  state_attention_evidence=${4-}
  state_attention_signature=${5-}
  state_acknowledged_signature=${6-}
  state_source=${7-passive}
  state_identity=${8-}
  state_evidence=${9-}
  previous_state=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_state')
  previous_attention_signature=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_attention_signature')
  previous_acknowledged_signature=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_acknowledged_signature')
  previous_identity=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_identity')

  if [ -n "$state_identity" ] && [ -n "$previous_identity" ] &&
    [ "$state_identity" != "$previous_identity" ]; then
    previous_state=
    previous_attention_signature=
    previous_acknowledged_signature=
  fi

  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_type' "$state_agent_type"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_state_source' "$state_source"
  if [ -n "$state_identity" ]; then
    tmux set-option -pq -t "$state_pane_id" '@tmux_agents_identity' "$state_identity"
  fi
  if [ -n "$state_evidence" ]; then
    tmux set-option -pq -t "$state_pane_id" '@tmux_agents_evidence' "$state_evidence"
  else
    tmux set-option -puq -t "$state_pane_id" '@tmux_agents_evidence' 2>/dev/null || true
  fi

  if state_starts_new_wait "$previous_state" "$previous_attention_signature" \
    "$previous_acknowledged_signature" "$state_next" "$state_attention_signature" \
    "$state_acknowledged_signature"; then
    tmux set-option -pq -t "$state_pane_id" '@tmux_agents_state_since' "$(date +%s)"
  fi

  if [ -n "$state_attention_evidence" ] && [ -n "$state_attention_signature" ]; then
    tmux set-option -pq -t "$state_pane_id" '@tmux_agents_attention_evidence' "$state_attention_evidence"
    tmux set-option -pq -t "$state_pane_id" '@tmux_agents_attention_signature' "$state_attention_signature"
    if [ -n "$state_acknowledged_signature" ]; then
      tmux set-option -pq -t "$state_pane_id" '@tmux_agents_acknowledged_signature' "$state_acknowledged_signature"
    else
      tmux set-option -puq -t "$state_pane_id" '@tmux_agents_acknowledged_signature' 2>/dev/null || true
    fi
  else
    state_clear_attention_event "$state_pane_id"
  fi

  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_state' "$state_next"
}

state_acknowledge_agent() {
  state_transition_agent "$1" "$2" "$3" "$4" "$5" "$5" "$6" "$7" "$8"
}

state_apply_event() {
  state_event=$1
  shift

  case "$state_event" in
    transition) state_transition_agent "$@" ;;
    acknowledge) state_acknowledge_agent "$@" ;;
    remove) state_remove_agent "$@" ;;
    *) return 1 ;;
  esac

  if [ "${tmux_agents_state_batching:-0}" -eq 0 ]; then
    state_refresh
  fi
}

state_begin_reconciliation() {
  tmux_agents_state_batching=1
}

state_end_reconciliation() {
  tmux_agents_state_batching=0
  state_refresh
}

state_refresh_counts() {
  state_attention_count=0
  state_running_count=0
  state_stale_count=0
  state_total_count=0

  while IFS= read -r state_pane_id; do
    case "$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_state')" in
      attention) state_attention_count=$((state_attention_count + 1)) ;;
      running) state_running_count=$((state_running_count + 1)) ;;
      stale) state_stale_count=$((state_stale_count + 1)) ;;
      *) continue ;;
    esac
    state_total_count=$((state_total_count + 1))
  done < <(tmux list-panes -a -F '#{pane_id}')

  tmux set-option -gq '@tmux_agents_count_attention' "$state_attention_count"
  tmux set-option -gq '@tmux_agents_count_running' "$state_running_count"
  tmux set-option -gq '@tmux_agents_count_stale' "$state_stale_count"
  tmux set-option -gq '@tmux_agents_count_total' "$state_total_count"
}

state_render_status() {
  state_attention_count=$(tmux show-options -gqv '@tmux_agents_count_attention')
  state_running_count=$(tmux show-options -gqv '@tmux_agents_count_running')
  state_stale_count=$(tmux show-options -gqv '@tmux_agents_count_stale')
  state_status_value='#[fg=colour244]󰚩'

  if [ "$state_attention_count" -gt 0 ]; then
    state_status_value="$state_status_value #[fg=colour208]#[fg=colour232,bg=colour208]$state_attention_count#[fg=colour208,bg=default]"
  fi
  if [ "$state_running_count" -gt 0 ]; then
    state_status_value="$state_status_value #[fg=colour40]$state_running_count"
  fi
  if [ "$state_attention_count" -gt 0 ] || [ "$state_running_count" -gt 0 ]; then
    state_status_value="$state_status_value #[fg=colour244]$state_stale_count#[default]"
  else
    state_status_value="$state_status_value $state_stale_count#[default]"
  fi

  tmux set-option -gq '@tmux_agents_status' "$state_status_value"
}

state_refresh() {
  state_refresh_counts
  state_render_status
}

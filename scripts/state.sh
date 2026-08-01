#!/usr/bin/env bash

# Shared pane-state boundary. Callers supply event evidence, never screen text.

state_script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=panes.sh
. "$state_script_root/scripts/panes.sh"

state_with_lock() (
  state_lock_acquired=0
  trap '[ "$state_lock_acquired" -eq 0 ] || tmux wait-for -U tmux-agents-state >/dev/null 2>&1 || true' EXIT
  tmux wait-for -L tmux-agents-state
  state_lock_acquired=1
  "$@"
)

state_debug() {
  state_debug_message=$1

  [ "${tmux_agents_debug_scanning:-0}" = '1' ] || return 0
  if [ -z "${tmux_agents_debug_enabled+x}" ]; then
    tmux_agents_debug_enabled=$(tmux show-options -gqv '@tmux_agents_debug' || true)
  fi
  [ "$tmux_agents_debug_enabled" = '1' ] || return 0
  tmux display-message -d 0 "tmux-agents debug: $state_debug_message" \
    2>/dev/null || true
}

state_clear_attention_event() {
  state_pane_id=$1

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_attention_evidence' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_attention_signature' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_acknowledged_signature' 2>/dev/null || true
}

state_clear_fallback_schedule() {
  state_pane_id=$1

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_fallback_after' \
    2>/dev/null || true
}

state_clear_host_metadata() {
  state_pane_id=$1

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_host' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_nvim_server' \
    2>/dev/null || true
}

state_record_sidekick_host() {
  state_pane_id=$1
  state_nvim_server=$2

  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_host' 'sidekick'
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_nvim_server' \
    "$state_nvim_server"
}

state_remove_agent() {
  state_pane_id=$1
  state_existing_type=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_type')
  state_existing_state=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_state')

  if [ -n "$state_existing_type" ] || [ -n "$state_existing_state" ]; then
    state_debug "remove pane=$state_pane_id"
  fi

  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_type' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_identity' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_process_identity' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_last_hook_at' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state_source' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_evidence' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state' 2>/dev/null || true
  tmux set-option -puq -t "$state_pane_id" '@tmux_agents_state_since' 2>/dev/null || true
  state_clear_attention_event "$state_pane_id"
  state_clear_fallback_schedule "$state_pane_id"
  state_clear_host_metadata "$state_pane_id"
}

state_register_discovered_agent_unlocked() {
  state_pane_id=$1
  state_agent_type=$2
  state_process_identity=$3
  state_grace_seconds=$4
  state_recorded_process_identity=$(tmux show-options -pqv -t "$state_pane_id" \
    '@tmux_agents_process_identity')
  state_source=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_state_source')
  state_recorded_type=$(tmux show-options -pqv -t "$state_pane_id" '@tmux_agents_type')

  if [ "$state_source" = 'hook' ] && [ -z "$state_recorded_process_identity" ] &&
    [ "$state_recorded_type" = "$state_agent_type" ]; then
    state_record_process_identity "$state_pane_id" "$state_process_identity"
    return 0
  fi
  if [ "$state_source" = 'hook' ] &&
    [ "$state_recorded_process_identity" = "$state_process_identity" ]; then
    return 0
  fi
  if [ "$state_recorded_process_identity" = "$state_process_identity" ] &&
    { [ "$state_source" = 'grace' ] || [ "$state_source" = 'passive' ]; }; then
    return 0
  fi

  state_remove_agent "$state_pane_id"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_type' "$state_agent_type"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_identity' "$state_process_identity"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_process_identity' \
    "$state_process_identity"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_state_source' 'grace'
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_fallback_after' \
    "$(( $(date +%s) + state_grace_seconds ))"
  state_debug "discover pane=$state_pane_id type=$state_agent_type identity=$state_process_identity"
}

state_register_discovered_agent() {
  state_with_lock state_register_discovered_agent_unlocked "$@"
}

state_record_process_identity() {
  state_pane_id=$1
  state_process_identity=$2

  if [ "$(tmux show-options -pqv -t "$state_pane_id" \
    '@tmux_agents_process_identity')" = "$state_process_identity" ]; then
    return 0
  fi

  tmux set-option -pq -t "$state_pane_id" \
    '@tmux_agents_process_identity' "$state_process_identity"
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
  previous_record=$(tmux display-message -p -t "$state_pane_id" \
    '#{@tmux_agents_state}|#{@tmux_agents_attention_evidence}|#{@tmux_agents_attention_signature}|#{@tmux_agents_acknowledged_signature}|#{@tmux_agents_identity}|#{@tmux_agents_type}|#{@tmux_agents_state_source}|#{@tmux_agents_evidence}|#{@tmux_agents_fallback_after}')
  IFS='|' read -r previous_state previous_attention_evidence \
    previous_attention_signature previous_acknowledged_signature \
    previous_identity previous_type previous_source previous_evidence \
    previous_fallback_after <<EOF
$previous_record
EOF
  desired_identity=$previous_identity
  if [ -n "$state_identity" ]; then
    desired_identity=$state_identity
  fi
  desired_attention_evidence=
  desired_attention_signature=
  desired_acknowledged_signature=
  if [ -n "$state_attention_evidence" ] && [ -n "$state_attention_signature" ]; then
    desired_attention_evidence=$state_attention_evidence
    desired_attention_signature=$state_attention_signature
    desired_acknowledged_signature=$state_acknowledged_signature
  fi

  if [ "$previous_state" = "$state_next" ] &&
    [ "$previous_attention_evidence" = "$desired_attention_evidence" ] &&
    [ "$previous_attention_signature" = "$desired_attention_signature" ] &&
    [ "$previous_acknowledged_signature" = "$desired_acknowledged_signature" ] &&
    [ "$previous_identity" = "$desired_identity" ] &&
    [ "$previous_type" = "$state_agent_type" ] &&
    [ "$previous_source" = "$state_source" ] &&
    [ "$previous_evidence" = "$state_evidence" ] &&
    [ -z "$previous_fallback_after" ]; then
    return 0
  fi

  if [ "$previous_state" != "$state_next" ] ||
    { [ -n "$state_identity" ] && [ "$previous_identity" != "$state_identity" ]; }; then
    state_debug "transition pane=$state_pane_id type=$state_agent_type source=$state_source identity=$state_identity old=$previous_state new=$state_next evidence=$state_evidence"
  fi

  if [ -n "$state_identity" ] && [ -n "$previous_identity" ] &&
    [ "$state_identity" != "$previous_identity" ]; then
    previous_state=
    previous_attention_signature=
    previous_acknowledged_signature=
    state_clear_host_metadata "$state_pane_id"
  fi

  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_type' "$state_agent_type"
  tmux set-option -pq -t "$state_pane_id" '@tmux_agents_state_source' "$state_source"
  state_clear_fallback_schedule "$state_pane_id"
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

state_apply_event_unlocked() {
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

state_apply_event() {
  state_with_lock state_apply_event_unlocked "$@"
}

state_apply_event_if_current_unlocked() {
  state_expected_pane_id=$1
  state_expected_source=$2
  state_expected_identity=$3
  state_expected_state=$4
  state_expected_attention_signature=$5
  state_expected_acknowledged_signature=$6
  shift 6
  state_current_record=$(tmux display-message -p -t "$state_expected_pane_id" \
    '#{@tmux_agents_state_source}|#{@tmux_agents_identity}|#{@tmux_agents_state}|#{@tmux_agents_attention_signature}|#{@tmux_agents_acknowledged_signature}')
  IFS='|' read -r state_current_source state_current_identity \
    state_current_state state_current_attention_signature \
    state_current_acknowledged_signature <<EOF
$state_current_record
EOF

  if [ "$state_current_source" != "$state_expected_source" ] ||
    [ "$state_current_identity" != "$state_expected_identity" ] ||
    [ "$state_current_state" != "$state_expected_state" ] ||
    [ "$state_current_attention_signature" != "$state_expected_attention_signature" ] ||
    [ "$state_current_acknowledged_signature" != "$state_expected_acknowledged_signature" ]; then
    return 0
  fi

  state_apply_event_unlocked "$@"
}

state_apply_event_if_current() {
  state_with_lock state_apply_event_if_current_unlocked "$@"
}

state_begin_reconciliation() {
  tmux_agents_state_batching=1
}

state_end_reconciliation() {
  tmux_agents_state_batching=0
  state_with_lock state_refresh
}

state_refresh_counts() {
  state_attention_count=0
  state_running_count=0
  state_stale_count=0
  state_total_count=0

  while IFS='|' read -r state_pane_id state_pane_state _state_pane_fields; do
    case "$state_pane_state" in
      attention) state_attention_count=$((state_attention_count + 1)) ;;
      running) state_running_count=$((state_running_count + 1)) ;;
      stale) state_stale_count=$((state_stale_count + 1)) ;;
      *) continue ;;
    esac
    state_total_count=$((state_total_count + 1))
  done < <(pane_tracking_snapshot)

  state_set_global_option '@tmux_agents_count_attention' "$state_attention_count"
  state_set_global_option '@tmux_agents_count_running' "$state_running_count"
  state_set_global_option '@tmux_agents_count_stale' "$state_stale_count"
  state_set_global_option '@tmux_agents_count_total' "$state_total_count"
}

state_set_global_option() {
  state_option_name=$1
  state_option_value=$2

  if [ "$(tmux show-options -gqv "$state_option_name")" != "$state_option_value" ]; then
    tmux set-option -gq "$state_option_name" "$state_option_value"
    state_debug "set-option name=$state_option_name"
  fi
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

  state_set_global_option '@tmux_agents_status' "$state_status_value"
}

state_refresh() {
  state_refresh_counts
  state_render_status
  tmux refresh-client -S 2>/dev/null || true
}

state_refresh_safely() {
  state_with_lock state_refresh
}

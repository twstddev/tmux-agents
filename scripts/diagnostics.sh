#!/usr/bin/env bash

# Human-readable diagnostics for one reconciled Agent. This reports metadata
# and non-content integration checks only; it never captures a pane.

diagnostics_report_agent() {
  diagnostics_pane_id=$1
  diagnostics_agent_type=$2
  diagnostics_process_identity=$3
  diagnostics_nvim_process_id=$4
  diagnostics_nvim_server=$5
  diagnostics_source=$(tmux show-options -pqv -t "$diagnostics_pane_id" \
    '@tmux_agents_state_source')
  diagnostics_state=$(tmux show-options -pqv -t "$diagnostics_pane_id" \
    '@tmux_agents_state')
  diagnostics_identity=$(tmux show-options -pqv -t "$diagnostics_pane_id" \
    '@tmux_agents_identity')
  diagnostics_last_hook_at=$(tmux show-options -pqv -t "$diagnostics_pane_id" \
    '@tmux_agents_last_hook_at')
  diagnostics_host=$(tmux show-options -pqv -t "$diagnostics_pane_id" \
    '@tmux_agents_host')
  diagnostics_location=$(tmux display-message -p -t "$diagnostics_pane_id" \
    '#{session_name}:#{window_name}.#{pane_index}')

  case "$diagnostics_source" in
  hook)
    diagnostics_hook=healthy
    diagnostics_fallback=inactive
    ;;
  grace)
    diagnostics_hook=missing-startup-hook
    diagnostics_fallback=pending
    ;;
  passive)
    diagnostics_hook=missing
    diagnostics_fallback=active
    ;;
  *)
    diagnostics_hook=missing
    diagnostics_fallback=inactive
    ;;
  esac

  [ -n "$diagnostics_state" ] || diagnostics_state=unclassified
  [ -n "$diagnostics_identity" ] || diagnostics_identity=unknown
  [ -n "$diagnostics_last_hook_at" ] || diagnostics_last_hook_at=never

  if [ -z "$diagnostics_nvim_process_id" ]; then
    diagnostics_sidekick='standalone'
  else
    diagnostics_rpc_status=$(sidekick_rpc_status "$diagnostics_nvim_server")
    if sidekick_verifies_embedded_host "$diagnostics_agent_type" \
      "$diagnostics_nvim_server"; then
      diagnostics_sidekick='verified rpc=reachable'
    elif [ "$diagnostics_rpc_status" = 'reachable' ]; then
      diagnostics_sidekick='unsupported-host rpc=reachable'
    elif [ "$diagnostics_host" = 'sidekick' ]; then
      diagnostics_sidekick="previously-verified rpc=$diagnostics_rpc_status"
    else
      diagnostics_sidekick="unverified rpc=$diagnostics_rpc_status"
    fi

    if [ "$diagnostics_rpc_status" = 'unreachable' ]; then
      diagnostics_sidekick="$diagnostics_sidekick address=possibly-stale"
    fi
  fi

  printf 'pane=%s location=%s type=%s process=%s hook=%s last-hook-activity=%s identity=%s state=%s source=%s fallback=%s sidekick=%s\n' \
    "$diagnostics_pane_id" "$diagnostics_location" "$diagnostics_agent_type" \
    "${diagnostics_process_identity#pid:}" "$diagnostics_hook" \
    "$diagnostics_last_hook_at" "$diagnostics_identity" "$diagnostics_state" \
    "$diagnostics_source" "$diagnostics_fallback" "$diagnostics_sidekick"
}

diagnostics_report_uncontained_agent() {
  diagnostics_agent_type=$1
  diagnostics_agent_pid=$2

  printf 'pane=none location=outside-current-tmux-server type=%s process=%s hook=unavailable last-hook-activity=never identity=unknown state=untracked source=none fallback=inactive sidekick=unknown reason=no-containing-pane action=run-in-containing-tmux-server-or-start-agent-in-tmux\n' \
    "$diagnostics_agent_type" "$diagnostics_agent_pid"
}

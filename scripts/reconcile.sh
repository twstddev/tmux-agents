#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
reconcile_mode=${1-}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=discovery.sh
. "$plugin_root/scripts/discovery.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"
if [ "$reconcile_mode" = '--diagnostics' ]; then
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=diagnostics.sh
  . "$plugin_root/scripts/diagnostics.sh"
fi

grace_seconds=$(tmux show-options -gqv '@tmux_agents_hook_grace_seconds')
case "$grace_seconds" in
'' | *[!0-9]*) grace_seconds=2 ;;
esac

state_begin_reconciliation
discovery_capture_process_snapshot
nvim_agent_pids=
pane_root_pids=
tracked_pane_ids='|'
pane_records=$(tmux list-panes -a \
  -F '#{pane_id}|#{pane_pid}|#{@tmux_agents_type}|#{@tmux_agents_state}')

while IFS='|' read -r pane_id pane_pid recorded_type recorded_state; do
  if [ -z "$pane_root_pids" ]; then
    pane_root_pids=$pane_pid
  else
    pane_root_pids="$pane_root_pids,$pane_pid"
  fi
  if [ -n "$recorded_type" ] || [ -n "$recorded_state" ]; then
    tracked_pane_ids="${tracked_pane_ids}${pane_id}|"
  fi
done <<EOF
$pane_records
EOF

reconciliation_records=$(discovery_find_agent_descendants "$pane_records")
while IFS='|' read -r _pane_id _agent_type process_identity nvim_process_id; do
  if [ -n "$nvim_process_id" ]; then
    agent_pid=${process_identity#pid:}
    if [ -z "$nvim_agent_pids" ]; then
      nvim_agent_pids=$agent_pid
    else
      nvim_agent_pids="$nvim_agent_pids,$agent_pid"
    fi
  fi
done <<EOF
$reconciliation_records
EOF

discovery_capture_agent_environments "$nvim_agent_pids"

while IFS='|' read -r pane_id agent_type process_identity nvim_process_id; do
  [ -n "$pane_id" ] || continue
  if [ -z "$agent_type" ]; then
    case "$tracked_pane_ids" in
      *"|$pane_id|"*) state_apply_event remove "$pane_id" ;;
    esac
    continue
  fi

  state_register_discovered_agent "$pane_id" "$agent_type" "$process_identity" \
    "$grace_seconds"
  state_source=$(tmux show-options -pqv -t "$pane_id" \
    '@tmux_agents_state_source')
  nvim_server=
  if [ "$state_source" != 'hook' ] && [ -n "$nvim_process_id" ]; then
    agent_pid=${process_identity#pid:}
    nvim_server=$(discovery_find_nvim_server "$agent_pid")
    if sidekick_verifies_embedded_host "$agent_type" "$nvim_server"; then
      state_record_sidekick_host "$pane_id" "$nvim_server"
    else
      state_clear_host_metadata "$pane_id"
    fi
  elif [ "$state_source" != 'hook' ]; then
    state_clear_host_metadata "$pane_id"
  elif [ -n "$nvim_process_id" ]; then
    nvim_server=$(tmux show-options -pqv -t "$pane_id" \
      '@tmux_agents_nvim_server')
    if [ -z "$nvim_server" ] && [ "$reconcile_mode" = '--diagnostics' ]; then
      agent_pid=${process_identity#pid:}
      nvim_server=$(discovery_find_nvim_server "$agent_pid")
    fi
  fi

  if [ "$reconcile_mode" = '--diagnostics' ]; then
    diagnostics_report_agent "$pane_id" "$agent_type" "$process_identity" \
      "$nvim_process_id" "${nvim_server-}"
  fi
done <<EOF
$reconciliation_records
EOF

if [ "$reconcile_mode" = '--diagnostics' ]; then
  while IFS='|' read -r agent_type agent_pid; do
    [ -n "$agent_type" ] || continue
    diagnostics_report_uncontained_agent "$agent_type" "$agent_pid"
  done < <(discovery_find_uncontained_agents "$pane_root_pids")
fi

state_end_reconciliation
"$plugin_root/scripts/schedule.sh" fallback

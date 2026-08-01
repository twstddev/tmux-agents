#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=discovery.sh
. "$plugin_root/scripts/discovery.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"

grace_seconds=$(tmux show-options -gqv '@tmux_agents_hook_grace_seconds')
case "$grace_seconds" in
'' | *[!0-9]*) grace_seconds=2 ;;
esac

state_begin_reconciliation
discovery_capture_process_snapshot
reconciliation_records=
nvim_agent_pids=

while IFS='|' read -r pane_id pane_pid; do
  discovered_agent=$(discovery_find_agent_descendant "$pane_pid")
  if [ -z "$discovered_agent" ]; then
    reconciliation_record="$pane_id|||"
  else
    IFS='|' read -r agent_type process_identity nvim_process_id <<EOF
$discovered_agent
EOF
    reconciliation_record="$pane_id|$agent_type|$process_identity|$nvim_process_id"
    if [ -n "$nvim_process_id" ]; then
      agent_pid=${process_identity#pid:}
      if [ -z "$nvim_agent_pids" ]; then
        nvim_agent_pids=$agent_pid
      else
        nvim_agent_pids="$nvim_agent_pids,$agent_pid"
      fi
    fi
  fi

  if [ -z "$reconciliation_records" ]; then
    reconciliation_records=$reconciliation_record
  else
    reconciliation_records="$reconciliation_records
$reconciliation_record"
  fi
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_pid}')

discovery_capture_agent_environments "$nvim_agent_pids"

while IFS='|' read -r pane_id agent_type process_identity nvim_process_id; do
  [ -n "$pane_id" ] || continue
  if [ -z "$agent_type" ]; then
    state_apply_event remove "$pane_id"
    continue
  fi

  state_register_discovered_agent "$pane_id" "$agent_type" "$process_identity" \
    "$grace_seconds"
  state_source=$(tmux show-options -pqv -t "$pane_id" \
    '@tmux_agents_state_source')
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
  fi
done <<EOF
$reconciliation_records
EOF

state_end_reconciliation
"$plugin_root/scripts/schedule.sh" fallback

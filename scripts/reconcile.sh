#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=discovery.sh
. "$plugin_root/scripts/discovery.sh"

grace_seconds=$(tmux show-options -gqv '@tmux_agents_hook_grace_seconds')
case "$grace_seconds" in
'' | *[!0-9]*) grace_seconds=2 ;;
esac

state_begin_reconciliation
discovery_capture_process_snapshot

while IFS='|' read -r pane_id pane_pid; do
  discovered_agent=$(discovery_find_agent_descendant "$pane_pid")
  if [ -z "$discovered_agent" ]; then
    state_apply_event remove "$pane_id"
    continue
  fi

  IFS='|' read -r agent_type process_identity <<EOF
$discovered_agent
EOF
  state_register_discovered_agent "$pane_id" "$agent_type" "$process_identity" \
    "$grace_seconds"
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_pid}')

state_end_reconciliation
"$plugin_root/scripts/schedule.sh" fallback

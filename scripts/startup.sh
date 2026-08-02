#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# tmux can load plugins before the first session and pane exist. The
# session-created hook installed by tmux-agents.tmux calls us again once pane
# discovery has a valid target.
first_pane=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | head -n 1 || true)
[ -n "$first_pane" ] || exit 0

"$plugin_root/scripts/reconcile.sh"
"$plugin_root/scripts/scan.sh"
"$plugin_root/scripts/schedule.sh" safety

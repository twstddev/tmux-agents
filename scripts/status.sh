#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=$1

"$plugin_root/scripts/scan.sh" "$selected_pane"
unknown_count=$(tmux show-options -gqv '@tmux_agents_count_unknown')
stale_count=$(tmux show-options -gqv '@tmux_agents_count_stale')

if [ "$unknown_count" -gt 0 ]; then
  status_value="#[fg=colour244]󰚩 #[fg=colour220]$unknown_count #[fg=colour244]$stale_count#[default]"
else
  status_value="#[fg=colour244]󰚩 $stale_count#[default]"
fi

tmux set-option -gq '@tmux_agents_status' "$status_value"

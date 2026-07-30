#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=$1

"$plugin_root/scripts/scan.sh" "$selected_pane"
attention_count=$(tmux show-options -gqv '@tmux_agents_count_attention')
running_count=$(tmux show-options -gqv '@tmux_agents_count_running')
unknown_count=$(tmux show-options -gqv '@tmux_agents_count_unknown')
stale_count=$(tmux show-options -gqv '@tmux_agents_count_stale')

status_value='#[fg=colour244]󰚩'

if [ "$attention_count" -gt 0 ]; then
  status_value="$status_value #[fg=colour208]#[fg=colour232,bg=colour208]$attention_count#[fg=colour208,bg=default]"
fi

if [ "$running_count" -gt 0 ]; then
  status_value="$status_value #[fg=colour40]$running_count"
fi

if [ "$unknown_count" -gt 0 ]; then
  status_value="$status_value #[fg=colour220]$unknown_count"
fi

if [ "$attention_count" -gt 0 ] || [ "$running_count" -gt 0 ] || [ "$unknown_count" -gt 0 ]; then
  status_value="$status_value #[fg=colour244]$stale_count#[default]"
else
  status_value="$status_value $stale_count#[default]"
fi

tmux set-option -gq '@tmux_agents_status' "$status_value"

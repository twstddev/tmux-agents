#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=$1

"$plugin_root/scripts/scan.sh" "$selected_pane"
stale_count=$(tmux show-options -gqv '@tmux_agents_count_stale')

tmux set-option -gq '@tmux_agents_status' "#[fg=colour244]󰚩 $stale_count#[default]"

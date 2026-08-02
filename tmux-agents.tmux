#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ "$(tmux show-options -gqv '@tmux_agents_plugin_root')" != "$plugin_root" ]; then
  tmux set-option -gq '@tmux_agents_plugin_root' "$plugin_root"
fi

ensure_count() {
  option_name=$1

  if [ -z "$(tmux show-options -gqv "$option_name")" ]; then
    tmux set-option -gq "$option_name" 0
  fi
}

install_placeholders() {
  option_name=$1
  option_value=$(tmux show-options -gqv "$option_name")
  status_command='#{@tmux_agents_status}'
  placeholders_installed=0

  case "$option_value" in
    *'#{tmux_agents}'*)
      option_value=${option_value//'#{tmux_agents}'/"$status_command"}
      placeholders_installed=1
      ;;
  esac

  if [ "$placeholders_installed" -eq 1 ]; then
    tmux set-option -gq "$option_name" "$option_value"
  fi
}

ensure_count '@tmux_agents_count_attention'
ensure_count '@tmux_agents_count_running'
ensure_count '@tmux_agents_count_stale'
ensure_count '@tmux_agents_count_total'

install_placeholders 'status-left'
install_placeholders 'status-right'

chooser_key=$(tmux show-options -gqv '@tmux_agents_chooser_key')
if [ -z "$chooser_key" ]; then
  chooser_key='A'
fi
tmux bind-key "$chooser_key" run-shell -b \
  "\"$plugin_root/scripts/choose.sh\" '#{client_name}' '#{pane_id}'"

jump_key=$(tmux show-options -gqv '@tmux_agents_jump_key')
if [ -z "$jump_key" ]; then
  jump_key='a'
fi
tmux bind-key "$jump_key" run-shell -b \
  "\"$plugin_root/scripts/jump.sh\" '#{client_name}' '#{pane_id}'"

tmux set-hook -g 'after-select-pane[1000]' \
  "run-shell -b \"\\\"$plugin_root/scripts/selection.sh\\\" '#{pane_id}'\""
tmux set-hook -g 'after-select-window[1000]' \
  "run-shell -b \"\\\"$plugin_root/scripts/selection.sh\\\" '#{pane_id}'\""
tmux set-hook -g 'pane-exited[1000]' \
  "run-shell -b \"\\\"$plugin_root/scripts/lifecycle.sh\\\"\""
tmux set-hook -g 'after-kill-pane[1000]' \
  "run-shell -b \"\\\"$plugin_root/scripts/lifecycle.sh\\\"\""

"$plugin_root/scripts/reconcile.sh"
"$plugin_root/scripts/scan.sh"
"$plugin_root/scripts/schedule.sh" safety

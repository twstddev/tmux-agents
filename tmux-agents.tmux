#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ensure_count() {
  option_name=$1

  if [ -z "$(tmux show-options -gqv "$option_name")" ]; then
    tmux set-option -gq "$option_name" 0
  fi
}

install_placeholders() {
  option_name=$1
  option_value=$(tmux show-options -gqv "$option_name")
  status_command="#{@tmux_agents_status}#('$plugin_root/scripts/status.sh' '#{pane_id}')"
  scan_command="#('$plugin_root/scripts/status.sh' '#{pane_id}')"
  placeholders_installed=0

  case "$option_value" in
    *'#{tmux_agents}'*)
      option_value=${option_value//'#{tmux_agents}'/"$status_command"}
      placeholders_installed=1
      ;;
  esac

  case "$option_value" in
    *'#{tmux_agents_scan}'*)
      option_value=${option_value//'#{tmux_agents_scan}'/"$scan_command"}
      placeholders_installed=1
      ;;
  esac

  if [ "$placeholders_installed" -eq 1 ]; then
    tmux set-option -gq "$option_name" "$option_value"
  fi
}

ensure_count '@tmux_agents_count_attention'
ensure_count '@tmux_agents_count_running'
ensure_count '@tmux_agents_count_unknown'
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

selected_pane=${1:-$(tmux display-message -p '#{pane_id}')}
"$plugin_root/scripts/status.sh" "$selected_pane"

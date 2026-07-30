#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ensure_count() {
  option_name=$1

  if [ -z "$(tmux show-options -gqv "$option_name")" ]; then
    tmux set-option -gq "$option_name" 0
  fi
}

install_placeholder() {
  option_name=$1
  option_value=$(tmux show-options -gqv "$option_name")
  status_command="#{@tmux_agents_status}#('$plugin_root/scripts/status.sh' '#{pane_id}')"

  case "$option_value" in
    *'#{tmux_agents}'*)
      option_value=${option_value//'#{tmux_agents}'/"$status_command"}
      tmux set-option -gq "$option_name" "$option_value"
      ;;
  esac
}

ensure_count '@tmux_agents_count_attention'
ensure_count '@tmux_agents_count_running'
ensure_count '@tmux_agents_count_unknown'
ensure_count '@tmux_agents_count_stale'
ensure_count '@tmux_agents_count_total'

install_placeholder 'status-left'
install_placeholder 'status-right'

selected_pane=${1:-$(tmux display-message -p '#{pane_id}')}
"$plugin_root/scripts/status.sh" "$selected_pane"

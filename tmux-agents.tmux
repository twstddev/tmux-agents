#!/bin/sh

set -eu

plugin_path=$(cd -- "$(dirname -- "$0")" && pwd)

tmux set-option -gq '@tmux_agents_plugin_path' "$plugin_path"

install_placeholder() {
  option_name=$1
  option_value=$(tmux show-options -gqv "$option_name")

  case "$option_value" in
    *'#{tmux_agents}'*)
      option_value=$(printf '%s\n' "$option_value" |
        sed 's/#{tmux_agents}/#{@tmux_agents_status}/g')
      tmux set-option -gq "$option_name" "$option_value"
      ;;
  esac
}

install_placeholder 'status-left'
install_placeholder 'status-right'

tmux set-hook -g 'after-kill-pane[1000]' \
  "run-shell -b \"\"$plugin_path/scripts/status.sh\"\""

"$plugin_path/scripts/status.sh"

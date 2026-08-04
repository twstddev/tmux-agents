#!/bin/sh

set -eu

plugin_path=$(CDPATH='' cd "$(dirname "$0")" && pwd)

tmux set-option -gq '@tmux_agents_plugin_path' "$plugin_path"

tmux bind-key -T prefix a run-shell -b \
  "\"$plugin_path/scripts/navigate.sh\" '#{client_name}'"

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
  "run-shell \"\"$plugin_path/scripts/status.sh\"\""

install_view_hook() {
  hook_name=$1
  tmux set-hook -g "${hook_name}[1000]" \
    "run-shell -b \"\"$plugin_path/scripts/hook.sh\" view '#{pane_id}'\""
}

install_view_hook 'after-select-pane'
install_view_hook 'after-select-window'
install_view_hook 'client-session-changed'
install_view_hook 'client-attached'

"$plugin_path/scripts/status.sh"

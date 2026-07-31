#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
schedule_kind=${1-}

has_fallback_panes() {
  while IFS= read -r pane_id; do
    case "$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_source')" in
    grace | passive) return 0 ;;
    esac
  done < <(tmux list-panes -a -F '#{pane_id}')

  return 1
}

schedule_once() {
  schedule_option=$1
  schedule_delay=$2
  schedule_command=$3

  [ "$(tmux show-options -gqv "$schedule_option")" = '1' ] && return 0
  tmux set-option -gq "$schedule_option" 1
  tmux run-shell -b -d "$schedule_delay" "$schedule_command"
}

case "$schedule_kind" in
fallback)
  has_fallback_panes || exit 0
  schedule_once '@tmux_agents_fallback_scheduled' 2 \
    "'$plugin_root/scripts/schedule.sh' run-fallback"
  ;;
safety)
  safety_interval=$(tmux show-options -gqv '@tmux_agents_safety_interval')
  case "$safety_interval" in
  '' | *[!0-9]* | 0) safety_interval=60 ;;
  esac
  schedule_once '@tmux_agents_safety_scheduled' "$safety_interval" \
    "'$plugin_root/scripts/schedule.sh' run-safety"
  ;;
run-fallback)
  tmux set-option -gu '@tmux_agents_fallback_scheduled'
  "$plugin_root/scripts/scan.sh"
  "$plugin_root/scripts/schedule.sh" fallback
  ;;
run-safety)
  tmux set-option -gu '@tmux_agents_safety_scheduled'
  "$plugin_root/scripts/reconcile.sh"
  "$plugin_root/scripts/schedule.sh" safety
  ;;
*) exit 0 ;;
esac

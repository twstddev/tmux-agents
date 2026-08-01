#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
schedule_kind=${1-}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=panes.sh
. "$plugin_root/scripts/panes.sh"

has_fallback_panes() {
  while IFS='|' read -r _pane_id _pane_state _pane_type pane_source _pane_fields; do
    case "$pane_source" in
    grace | passive) return 0 ;;
    esac
  done < <(pane_tracking_snapshot)

  return 1
}

schedule_once() (
  schedule_option=$1
  schedule_delay=$2
  schedule_command=$3

  schedule_lock_acquired=0
  trap '[ "$schedule_lock_acquired" -eq 0 ] || tmux wait-for -U tmux-agents-schedule >/dev/null 2>&1 || true' EXIT
  tmux wait-for -L tmux-agents-schedule
  schedule_lock_acquired=1

  [ "$(tmux show-options -gqv "$schedule_option")" = '1' ] && return 0
  tmux set-option -gq "$schedule_option" 1
  tmux run-shell -b -d "$schedule_delay" "$schedule_command"
)

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
  tmux set-option -gu '@tmux_agents_fallback_scheduled' 2>/dev/null || true
  "$plugin_root/scripts/scan.sh" || true
  "$plugin_root/scripts/schedule.sh" fallback
  ;;
run-safety)
  tmux set-option -gu '@tmux_agents_safety_scheduled' 2>/dev/null || true
  "$plugin_root/scripts/reconcile.sh" || true
  "$plugin_root/scripts/schedule.sh" safety
  ;;
*) exit 0 ;;
esac

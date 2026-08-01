#!/usr/bin/env bash

set -e

event_name=${1-}
tmux_agents_root=$(tmux show-options -gqv '@tmux_agents_plugin_root' \
  2>/dev/null || true)

[ -x "$tmux_agents_root/scripts/hook.sh" ] || exit 0
exec "$tmux_agents_root/scripts/hook.sh" claude "$event_name"

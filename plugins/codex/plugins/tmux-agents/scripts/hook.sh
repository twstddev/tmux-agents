#!/bin/sh

set -eu

operation=${1-}
case "$operation" in
  mark|clear) ;;
  *) exit 0 ;;
esac

[ -n "${TMUX-}" ] || exit 0

plugin_path=$(tmux show-options -gqv '@tmux_agents_plugin_path' \
  2>/dev/null || true)
[ -n "$plugin_path" ] || exit 0
shared_hook="$plugin_path/scripts/hook.sh"

[ -x "$shared_hook" ] || exit 0
exec "$shared_hook" "$operation"

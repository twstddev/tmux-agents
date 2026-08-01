#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target_pane=${1-}

case "$target_pane" in
%*) ;;
*) exit 0 ;;
esac

# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"

if [ "$(tmux show-options -pqv -t "$target_pane" '@tmux_agents_host')" = 'sidekick' ]; then
  agent_type=$(tmux show-options -pqv -t "$target_pane" '@tmux_agents_type')
  nvim_server=$(tmux show-options -pqv -t "$target_pane" \
    '@tmux_agents_nvim_server')

  if ! sidekick_visibility=$(sidekick_terminal_visibility "$agent_type" \
    "$nvim_server"); then
    printf '%s\n\n' \
      'Sidekick visibility is unavailable; selecting the Agent will still try to open it.'
  elif [ "$sidekick_visibility" = 'hidden' ]; then
    printf '%s\n\n' \
      'Sidekick Agent is hidden; selecting it will open and focus the Agent.'
  fi
fi

tmux capture-pane -p -e -t "$target_pane"

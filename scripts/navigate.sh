#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
client_name=${1-}
target_pane=${2-}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"

tmux switch-client -c "$client_name" -t "$target_pane"

if [ "$(tmux show-options -pqv -t "$target_pane" '@tmux_agents_host')" = 'sidekick' ]; then
  agent_type=$(tmux show-options -pqv -t "$target_pane" '@tmux_agents_type')
  nvim_server=$(tmux show-options -pqv -t "$target_pane" \
    '@tmux_agents_nvim_server')

  if ! sidekick_show_and_focus "$agent_type" "$nvim_server"; then
    tmux display-message -c "$client_name" \
      'tmux-agents: Sidekick could not show the Agent'
  fi
fi

"$plugin_root/scripts/selection.sh" "$target_pane"

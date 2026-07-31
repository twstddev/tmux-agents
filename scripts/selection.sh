#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=${1-}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"

state_begin_reconciliation
while IFS= read -r pane_id; do
  pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
  pane_type=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_type')
  pane_source=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_source')
  pane_identity=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_identity')
  pane_evidence=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_evidence')
  attention_evidence=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_evidence')
  attention_signature=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_signature')
  acknowledged_signature=$(tmux show-options -pqv -t "$pane_id" \
    '@tmux_agents_acknowledged_signature')

  [ "$pane_state" = 'attention' ] || continue
  [ -n "$pane_type" ] || continue

  if [ "$pane_id" = "$selected_pane" ]; then
    case "$attention_evidence" in
    input)
      state_apply_event acknowledge "$pane_id" "$pane_type" 'attention' 'input' \
        "$attention_signature" "$pane_source" "$pane_identity" "$pane_evidence"
      ;;
    result)
      state_apply_event acknowledge "$pane_id" "$pane_type" 'stale' 'result' \
        "$attention_signature" "$pane_source" "$pane_identity" "$pane_evidence"
      ;;
    esac
  elif [ "$attention_evidence" = 'input' ] &&
    [ "$acknowledged_signature" = "$attention_signature" ]; then
    state_apply_event transition "$pane_id" "$pane_type" 'attention' 'input' \
      "$attention_signature" '' "$pane_source" "$pane_identity" "$pane_evidence"
  fi
done < <(tmux list-panes -a -F '#{pane_id}')
state_end_reconciliation

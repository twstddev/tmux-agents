#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"

agent_type=${1-}
event_name=${2-}
hook_pane_id=${TMUX_PANE-}

case "$agent_type" in
codex | claude) ;;
*) exit 0 ;;
esac

case "$event_name" in
start | running | input | result | end) ;;
*) exit 0 ;;
esac

[ -n "$hook_pane_id" ] || exit 0
if ! tmux display-message -p -t "$hook_pane_id" '#{pane_id}' >/dev/null 2>&1; then
  exit 0
fi

hook_input=$(cat)

json_string() {
  json_key=$1

  printf '%s\n' "$hook_input" |
    sed -n 's/.*"'"$json_key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

session_identity=$(json_string session_id)
case "$session_identity" in
'' | *[!A-Za-z0-9._:-]*) exit 0 ;;
esac

turn_identity=$(json_string turn_id)
case "$turn_identity" in
*[!A-Za-z0-9._:-]*) turn_identity= ;;
esac

event_signature="$event_name:$session_identity"
if [ -n "$turn_identity" ]; then
  event_signature="$event_signature:$turn_identity"
fi

recorded_identity=$(tmux show-options -pqv -t "$hook_pane_id" \
  '@tmux_agents_identity')
recorded_source=$(tmux show-options -pqv -t "$hook_pane_id" \
  '@tmux_agents_state_source')

if [ "$event_name" = 'end' ]; then
  if [ "$recorded_source" != 'hook' ] ||
    [ "$recorded_identity" != "$session_identity" ]; then
    state_debug "hook ignored event=end pane=$hook_pane_id identity=$session_identity reason=identity-mismatch"
    exit 0
  fi

  state_debug "hook event=end pane=$hook_pane_id type=$agent_type identity=$session_identity"
  state_apply_event remove "$hook_pane_id"
  exit 0
fi

if [ "$event_name" != 'start' ] && [ "$recorded_source" = 'hook' ] &&
  [ -n "$recorded_identity" ] && [ "$recorded_identity" != "$session_identity" ]; then
  state_debug "hook ignored event=$event_name pane=$hook_pane_id identity=$session_identity reason=identity-mismatch"
  exit 0
fi

state_debug "hook event=$event_name pane=$hook_pane_id type=$agent_type identity=$session_identity"
tmux set-option -pq -t "$hook_pane_id" '@tmux_agents_last_hook_at' "$(date +%s)"

case "$event_name" in
start)
  state_apply_event transition "$hook_pane_id" "$agent_type" 'stale' '' '' '' \
    'hook' "$session_identity" 'session-start'
  ;;
running)
  state_apply_event transition "$hook_pane_id" "$agent_type" 'running' '' '' '' \
    'hook' "$session_identity" 'running'
  ;;
input)
  state_apply_event transition "$hook_pane_id" "$agent_type" 'attention' 'input' \
    "$event_signature" '' 'hook' "$session_identity" 'input'
  ;;
result)
  state_apply_event transition "$hook_pane_id" "$agent_type" 'attention' 'result' \
    "$event_signature" '' 'hook' "$session_identity" 'result'
  ;;
esac

state_clear_host_metadata "$hook_pane_id"
if sidekick_verifies_embedded_host "$agent_type" "${NVIM-}"; then
  state_record_sidekick_host "$hook_pane_id" "$NVIM"
fi

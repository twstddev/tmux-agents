#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
items_mode=0
if [ "${1-}" = '--items' ]; then
  items_mode=1
  client_name=
  selected_pane=${2-}
else
  client_name=${1-}
  selected_pane=${2-}
fi

state_label() {
  case "$1" in
  attention) printf '%s' 'Needs attention' ;;
  stale) printf '%s' 'Stale' ;;
  unknown) printf '%s' 'Unknown' ;;
  running) printf '%s' 'Running' ;;
  esac
}

agent_label() {
  case "$1" in
  codex) printf '%s' 'Codex' ;;
  claude) printf '%s' 'Claude Code' ;;
  esac
}

state_rank() {
  case "$1" in
  attention) printf '%s' 0 ;;
  stale) printf '%s' 1 ;;
  unknown) printf '%s' 2 ;;
  running) printf '%s' 3 ;;
  esac
}

state_age() {
  state_since=$1
  current_time=$2

  case "$state_since" in
  '' | *[!0-9]*) elapsed=0 ;;
  *)
    elapsed=$((current_time - state_since))
    if [ "$elapsed" -lt 0 ]; then
      elapsed=0
    fi
    ;;
  esac

  if [ "$elapsed" -lt 60 ]; then
    printf '%ss' "$elapsed"
  elif [ "$elapsed" -lt 3600 ]; then
    printf '%sm' "$((elapsed / 60))"
  elif [ "$elapsed" -lt 86400 ]; then
    printf '%sh' "$((elapsed / 3600))"
  else
    printf '%sd' "$((elapsed / 86400))"
  fi
}

sanitize_field() {
  printf '%s' "$1" |
    tr '\t\r\n' '   ' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

title_is_useful() {
  title_to_check=$1
  agent_type_to_check=$2
  agent_name_to_check=$3
  location_to_check=$4
  current_path_to_check=$5
  window_name_to_check=$6

  [ -n "$title_to_check" ] || return 1

  title_lower=$(printf '%s' "$title_to_check" | tr '[:upper:]' '[:lower:]')
  agent_name_lower=$(printf '%s' "$agent_name_to_check" | tr '[:upper:]' '[:lower:]')
  path_basename=${current_path_to_check##*/}

  case "$title_lower" in
  "$agent_type_to_check" | "$agent_name_lower") return 1 ;;
  esac
  case "$title_to_check" in
  "$location_to_check" | "$current_path_to_check" | "$path_basename" | "$window_name_to_check")
    return 1
    ;;
  esac

  return 0
}

ordered_agent_ids() {
  while IFS= read -r pane_id; do
    pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
    case "$pane_state" in
    attention | stale | unknown | running) ;;
    *) continue ;;
    esac

    pane_since=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_since')
    case "$pane_since" in
    '' | *[!0-9]*) pane_since=0 ;;
    esac
    if [ "$pane_state" != 'attention' ]; then
      pane_since=0
    fi

    printf '%s\t%020d\t%s\n' \
      "$(state_rank "$pane_state")" "$pane_since" "$pane_id"
  done < <(tmux list-panes -a -F '#{pane_id}') |
    LC_ALL=C sort -t $'\t' -k1,1n -k2,2n -k3,3
}

chooser_items() {
  current_time=$(date +%s)

  while IFS=$'\t' read -r _rank _state_since pane_id; do
    pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
    pane_since=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_since')
    pane_type=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_type')
    session_name=$(sanitize_field \
      "$(tmux display-message -p -t "$pane_id" '#{session_name}')")
    window_name=$(sanitize_field \
      "$(tmux display-message -p -t "$pane_id" '#{window_name}')")
    pane_index=$(tmux display-message -p -t "$pane_id" '#{pane_index}')
    pane_path=$(sanitize_field \
      "$(tmux display-message -p -t "$pane_id" '#{pane_current_path}')")
    pane_title=$(sanitize_field \
      "$(tmux display-message -p -t "$pane_id" '#{pane_title}')")
    pane_location="$session_name:$window_name.$pane_index"
    pane_agent_label=$(agent_label "$pane_type")
    details="$(state_label "$pane_state") · $pane_agent_label · $pane_location · $pane_path · $(state_age "$pane_since" "$current_time")"

    if title_is_useful "$pane_title" "$pane_type" "$pane_agent_label" \
      "$pane_location" "$pane_path" "$window_name"; then
      display="$pane_title
$details"
    else
      display=$details
    fi

    printf '%s\t%s\0' "$pane_id" "$display"
  done < <(ordered_agent_ids)
}

if [ "$items_mode" -eq 1 ]; then
  "$plugin_root/scripts/scan.sh" "$selected_pane"
  chooser_items
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message -c "$client_name" 'tmux-agents: fzf is required for the chooser'
  exit 0
fi

reload_command="\"$plugin_root/scripts/choose.sh\" --items \"$selected_pane\""

if ! selection=$(
  printf '\t%s\0' 'Loading Agents…' |
    fzf --read0 \
      --tmux=center,80%,80% \
      --delimiter=$'\t' \
      --with-nth=2.. \
      --layout=reverse \
      --prompt='Agents> ' \
      --bind="start:reload-sync($reload_command)" \
      --preview-window='right,60%,wrap' \
      --preview="case {1} in %*) tmux capture-pane -p -e -t {1} ;; esac"
); then
  exit 0
fi

target_pane=${selection%%$'\t'*}
case "$target_pane" in
%*)
  case "${target_pane#%}" in
  '' | *[!0-9]*) exit 0 ;;
  esac
  ;;
*) exit 0 ;;
esac

if ! tmux display-message -p -t "$target_pane" '#{pane_id}' >/dev/null 2>&1; then
  exit 0
fi

tmux switch-client -c "$client_name" -t "$target_pane"
tmux run-shell -b "\"$plugin_root/scripts/scan.sh\" '$target_pane'"

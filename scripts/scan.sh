#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmux_agents_debug_scanning=1

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sidekick.sh
. "$plugin_root/scripts/sidekick.sh"
state_begin_reconciliation

screen_shows_running() {
  agent_type_to_check=$1

  awk -v agent_type="$agent_type_to_check" '
    agent_type == "codex" &&
      $0 ~ "^[[:space:]]*•[[:space:]]+Working[[:space:]]*\\(" &&
      /esc to interrupt/ {
        running_line = NR
        nonblank_lines_after_running = 0
      }
    agent_type == "claude" &&
      $0 ~ "^[[:space:]]*(✻|✽|✶|✢|⚗)[[:space:]]+" &&
      /esc to interrupt/ {
        running_line = NR
        nonblank_lines_after_running = 0
      }
    running_line && NR > running_line && /[^[:space:]]/ {
      nonblank_lines_after_running++
    }
    END {
      if (!running_line || nonblank_lines_after_running > 3) {
        exit 1
      }
    }
  '
}

screen_shows_input_request() {
  agent_type_to_check=$1

  awk -v agent_type="$agent_type_to_check" '
    agent_type == "codex" &&
      /Would you like to run the following command\?/ {
        request_header = NR
      }
    agent_type == "codex" &&
      /^Question [[:digit:]]+\/[[:digit:]]+$/ {
        request_header = NR
      }
    agent_type == "codex" && request_header &&
      /Press enter to (confirm|submit) or esc to cancel/ {
        request_footer = NR
      }
    agent_type == "claude" &&
      /Do you want to proceed\?/ {
        request_header = NR
      }
    agent_type == "claude" &&
      /^Question [[:digit:]]+\/[[:digit:]]+$/ {
        request_header = NR
      }
    agent_type == "claude" && request_header &&
      /(Esc|esc) to cancel/ {
        request_footer = NR
      }
    /[^[:space:]]/ { last_nonblank_line = NR }
    END {
      if (!request_header || !request_footer ||
          request_footer < request_header ||
          last_nonblank_line - request_footer > 1) {
        exit 1
      }
    }
  '
}

while IFS='|' read -r pane_id pane_state pane_type pane_state_source \
  pane_identity _pane_process_identity _pane_evidence _pane_state_since \
  pane_attention_evidence pane_attention_signature pane_acknowledged_signature \
  fallback_after pane_host pane_nvim_server; do
  pane_observed_source=$pane_state_source

  case "$pane_state_source" in
  grace)
    case "$fallback_after" in
    '' | *[!0-9]*) continue ;;
    esac
    if [ "$(date +%s)" -lt "$fallback_after" ]; then
      continue
    fi
    pane_state_source='passive'
    ;;
  passive) ;;
  *) continue ;;
  esac

  case "$pane_type" in
    codex) prompt_marker='›' ;;
    claude) prompt_marker='❯' ;;
    *)
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" remove "$pane_id"
      continue
      ;;
  esac

  if [ "$pane_host" = 'sidekick' ]; then
    if ! sidekick_visibility=$(sidekick_terminal_visibility "$pane_type" \
      "$pane_nvim_server"); then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'stale' '' '' '' 'passive' "$pane_identity" \
        'sidekick-visibility-unavailable'
      continue
    elif [ "$sidekick_visibility" = 'hidden' ]; then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'stale' '' '' '' 'passive' "$pane_identity" 'hidden-sidekick'
      continue
    fi
  fi

  current_screen=$(tmux capture-pane -p -t "$pane_id")
  current_screen_signature=$(printf '%s\n' "$current_screen" | cksum | awk '{ print $1 ":" $2 }')

  if printf '%s\n' "$current_screen" | screen_shows_input_request "$pane_type"; then
    if [ "$pane_acknowledged_signature" = "$current_screen_signature" ]; then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" acknowledge "$pane_id" "$pane_type" \
        'attention' 'input' "$current_screen_signature" 'passive' \
        "$pane_identity" 'input'
    else
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'attention' 'input' "$current_screen_signature" '' 'passive' \
        "$pane_identity" 'input'
    fi
  elif printf '%s\n' "$current_screen" | screen_shows_running "$pane_type"; then
    state_apply_event_if_current "$pane_id" "$pane_observed_source" \
      "$pane_identity" "$pane_state" "$pane_attention_signature" \
      "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
      'running' '' '' '' 'passive' "$pane_identity" 'running'
  elif printf '%s\n' "$current_screen" | awk -v prompt_marker="$prompt_marker" '
    $0 ~ "^[[:space:]]*" prompt_marker { prompt_line = NR }
    /[^[:space:]]/ { last_nonblank_line = NR }
    END {
      if (!prompt_line || last_nonblank_line - prompt_line > 3) {
        exit 1
      }
    }
  '; then
    if [ "$pane_state" = 'running' ]; then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'attention' 'result' "$current_screen_signature" '' 'passive' \
        "$pane_identity" 'result'
    elif [ "$pane_attention_evidence" = 'input' ] &&
      [ "$pane_attention_signature" != "$current_screen_signature" ]; then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'attention' 'result' "$current_screen_signature" '' 'passive' \
        "$pane_identity" 'result'
    elif [ -z "$pane_state" ]; then
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        'stale' '' '' '' 'passive' "$pane_identity" 'idle'
    else
      state_apply_event_if_current "$pane_id" "$pane_observed_source" \
        "$pane_identity" "$pane_state" "$pane_attention_signature" \
        "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
        "$pane_state" "$pane_attention_evidence" "$pane_attention_signature" \
        "$pane_acknowledged_signature" 'passive' "$pane_identity" 'idle'
    fi
  else
    state_apply_event_if_current "$pane_id" "$pane_observed_source" \
      "$pane_identity" "$pane_state" "$pane_attention_signature" \
      "$pane_acknowledged_signature" transition "$pane_id" "$pane_type" \
      'stale' '' '' '' 'passive' "$pane_identity" 'unmatched-screen'
  fi
done < <(pane_tracking_snapshot)

state_end_reconciliation

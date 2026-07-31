#!/usr/bin/env bash

set -e

selected_pane=$1
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmux_agents_debug_scanning=1

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=discovery.sh
. "$plugin_root/scripts/discovery.sh"

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

discovery_capture_process_snapshot

while IFS='|' read -r pane_id pane_pid; do
  discovered_agent=$(discovery_find_agent_descendant "$pane_pid")
  if [ -z "$discovered_agent" ]; then
    state_apply_event remove "$pane_id"
    continue
  fi

  printf '%s|%s\n' "$pane_id" "$discovered_agent"
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_pid}') |
while IFS='|' read -r pane_id pane_command pane_process_identity; do
  pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
  pane_attention_evidence=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_evidence')
  pane_attention_signature=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_signature')
  pane_acknowledged_signature=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_acknowledged_signature')
  pane_state_source=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state_source')
  pane_identity=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_identity')
  recorded_process_identity=$(tmux show-options -pqv -t "$pane_id" \
    '@tmux_agents_process_identity')

  case "$pane_command" in
    codex) prompt_marker='›' ;;
    claude) prompt_marker='❯' ;;
    *)
      state_apply_event remove "$pane_id"
      continue
      ;;
  esac

  if [ "$pane_state_source" = 'hook' ] &&
    [ "$recorded_process_identity" != "$pane_process_identity" ]; then
    state_apply_event transition "$pane_id" "$pane_command" 'stale' '' '' '' \
      'passive' "$pane_process_identity" 'process-replaced'
    pane_state='stale'
    pane_attention_evidence=
    pane_attention_signature=
    pane_acknowledged_signature=
    pane_state_source='passive'
    pane_identity="$pane_process_identity"
  fi
  state_record_process_identity "$pane_id" "$pane_process_identity"

  if [ "$pane_state_source" = 'hook' ]; then
    if [ "$pane_state" = 'attention' ]; then
      if [ "$pane_id" = "$selected_pane" ]; then
        case "$pane_attention_evidence" in
        input)
          state_apply_event acknowledge "$pane_id" "$pane_command" 'attention' 'input' \
            "$pane_attention_signature" 'hook' "$pane_identity" 'input'
          ;;
        result)
          state_apply_event acknowledge "$pane_id" "$pane_command" 'stale' 'result' \
            "$pane_attention_signature" 'hook' "$pane_identity" 'result'
          ;;
        esac
      elif [ "$pane_attention_evidence" = 'input' ] &&
        [ "$pane_acknowledged_signature" = "$pane_attention_signature" ]; then
        state_apply_event transition "$pane_id" "$pane_command" 'attention' 'input' \
          "$pane_attention_signature" '' 'hook' "$pane_identity" 'input'
      fi
    fi

    if [ "$pane_state" = 'attention' ] &&
      [ "$pane_attention_evidence" = 'input' ] &&
      [ "$pane_acknowledged_signature" = "$pane_attention_signature" ]; then
      current_screen=$(tmux capture-pane -p -t "$pane_id")
      if printf '%s\n' "$current_screen" | screen_shows_running "$pane_command"; then
        state_apply_event transition "$pane_id" "$pane_command" 'running' '' '' '' \
          'hook' "$pane_identity" 'running-screen'
      fi
    fi
    continue
  fi

  current_screen=$(tmux capture-pane -p -t "$pane_id")
  current_screen_signature=$(printf '%s\n' "$current_screen" | cksum | awk '{ print $1 ":" $2 }')

  if printf '%s\n' "$current_screen" | screen_shows_input_request "$pane_command"; then
    if [ "$pane_id" = "$selected_pane" ]; then
      state_apply_event acknowledge "$pane_id" "$pane_command" 'attention' 'input' \
        "$current_screen_signature" 'passive' "$pane_process_identity" 'input'
    else
      state_apply_event transition "$pane_id" "$pane_command" 'attention' 'input' \
        "$current_screen_signature" '' 'passive' "$pane_process_identity" 'input'
    fi
  elif printf '%s\n' "$current_screen" | screen_shows_running "$pane_command"; then
    state_apply_event transition "$pane_id" "$pane_command" 'running' '' '' '' \
      'passive' "$pane_process_identity" 'running'
  elif printf '%s\n' "$current_screen" | awk -v prompt_marker="$prompt_marker" '
    $0 ~ "^[[:space:]]*" prompt_marker { prompt_line = NR }
    /[^[:space:]]/ { last_nonblank_line = NR }
    END {
      if (!prompt_line || last_nonblank_line - prompt_line > 3) {
        exit 1
      }
    }
  '; then
    if [ "$pane_id" = "$selected_pane" ]; then
      if [ "$pane_state" = 'running' ] || [ "$pane_attention_evidence" = 'result' ]; then
        state_apply_event acknowledge "$pane_id" "$pane_command" 'stale' 'result' \
          "$current_screen_signature" 'passive' "$pane_process_identity" 'result'
      else
        state_apply_event transition "$pane_id" "$pane_command" 'stale' '' '' '' \
          'passive' "$pane_process_identity" 'idle'
      fi
    elif [ "$pane_state" = 'running' ]; then
      state_apply_event transition "$pane_id" "$pane_command" 'attention' 'result' \
        "$current_screen_signature" '' 'passive' "$pane_process_identity" 'result'
    elif [ "$pane_attention_evidence" = 'input' ] &&
      [ "$pane_attention_signature" != "$current_screen_signature" ]; then
      state_apply_event transition "$pane_id" "$pane_command" 'attention' 'result' \
        "$current_screen_signature" '' 'passive' "$pane_process_identity" 'result'
    elif [ -z "$pane_state" ]; then
      state_apply_event transition "$pane_id" "$pane_command" 'stale' '' '' '' \
        'passive' "$pane_process_identity" 'idle'
    else
      state_apply_event transition "$pane_id" "$pane_command" "$pane_state" \
        "$pane_attention_evidence" "$pane_attention_signature" \
        "$pane_acknowledged_signature" 'passive' "$pane_process_identity" 'idle'
    fi
  else
    state_apply_event transition "$pane_id" "$pane_command" 'stale' '' '' '' \
      'passive' "$pane_process_identity" 'unmatched-screen'
  fi
done

state_end_reconciliation

#!/usr/bin/env bash

set -e

selected_pane=$1
attention_count=0
running_count=0
unknown_count=0
stale_count=0
total_count=0

clear_attention_event() {
  pane_id_to_clear=$1

  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_attention_evidence' 2>/dev/null || true
  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_attention_signature' 2>/dev/null || true
  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_acknowledged_signature' 2>/dev/null || true
}

set_attention_event() {
  pane_id_to_set=$1
  attention_evidence_to_set=$2
  attention_signature_to_set=$3
  acknowledged_signature_to_set=${4-}

  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_attention_evidence' "$attention_evidence_to_set"
  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_attention_signature' "$attention_signature_to_set"
  if [ -n "$acknowledged_signature_to_set" ]; then
    tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_acknowledged_signature' "$acknowledged_signature_to_set"
  else
    tmux set-option -puq -t "$pane_id_to_set" '@tmux_agents_acknowledged_signature' 2>/dev/null || true
  fi
}

clear_agent_state() {
  pane_id_to_clear=$1

  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_type' 2>/dev/null || true
  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_state' 2>/dev/null || true
  tmux set-option -puq -t "$pane_id_to_clear" '@tmux_agents_state_since' 2>/dev/null || true
  clear_attention_event "$pane_id_to_clear"
}

starts_new_wait() {
  next_state=$1
  next_attention_signature=$2
  next_acknowledged_signature=$3

  if [ "$pane_state" != "$next_state" ]; then
    return 0
  fi
  if [ "$next_state" != 'attention' ] || [ -z "$next_attention_signature" ]; then
    return 1
  fi
  if [ "$pane_attention_signature" != "$next_attention_signature" ]; then
    return 0
  fi

  [ -z "$next_acknowledged_signature" ] &&
    [ "$pane_acknowledged_signature" = "$next_attention_signature" ]
}

set_agent_state() {
  pane_id_to_set=$1
  agent_type_to_set=$2
  state_to_set=$3
  attention_evidence_to_set=${4-}
  attention_signature_to_set=${5-}
  acknowledged_signature_to_set=${6-}

  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_type' "$agent_type_to_set"
  if starts_new_wait "$state_to_set" "$attention_signature_to_set" \
    "$acknowledged_signature_to_set"; then
    tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_state_since' "$(date +%s)"
  fi

  if [ -n "$attention_evidence_to_set" ] && [ -n "$attention_signature_to_set" ]; then
    set_attention_event "$pane_id_to_set" "$attention_evidence_to_set" \
      "$attention_signature_to_set" "$acknowledged_signature_to_set"
  else
    clear_attention_event "$pane_id_to_set"
  fi

  tmux set-option -pq -t "$pane_id_to_set" '@tmux_agents_state' "$state_to_set"
  pane_state=$state_to_set
  pane_attention_evidence=$attention_evidence_to_set
  pane_attention_signature=$attention_signature_to_set
  pane_acknowledged_signature=$acknowledged_signature_to_set
}

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

while IFS='|' read -r pane_id pane_command; do
  pane_state=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_state')
  pane_attention_evidence=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_evidence')
  pane_attention_signature=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_attention_signature')
  pane_acknowledged_signature=$(tmux show-options -pqv -t "$pane_id" '@tmux_agents_acknowledged_signature')

  case "$pane_command" in
    codex) prompt_marker='›' ;;
    claude) prompt_marker='❯' ;;
    *)
      clear_agent_state "$pane_id"
      continue
      ;;
  esac

  current_screen=$(tmux capture-pane -p -t "$pane_id")
  current_screen_signature=$(printf '%s\n' "$current_screen" | cksum | awk '{ print $1 ":" $2 }')
  if printf '%s\n' "$current_screen" | screen_shows_input_request "$pane_command"; then
    if [ "$pane_id" = "$selected_pane" ]; then
      set_agent_state "$pane_id" "$pane_command" 'attention' 'input' \
        "$current_screen_signature" "$current_screen_signature"
    else
      set_agent_state "$pane_id" "$pane_command" 'attention' 'input' "$current_screen_signature"
    fi
  elif printf '%s\n' "$current_screen" | screen_shows_running "$pane_command"; then
    set_agent_state "$pane_id" "$pane_command" 'running'
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
        set_agent_state "$pane_id" "$pane_command" 'stale' 'result' \
          "$current_screen_signature" "$current_screen_signature"
      else
        set_agent_state "$pane_id" "$pane_command" 'stale'
      fi
    elif [ "$pane_state" = 'running' ]; then
      set_agent_state "$pane_id" "$pane_command" 'attention' 'result' "$current_screen_signature"
    elif [ "$pane_attention_evidence" = 'input' ] &&
      [ "$pane_attention_signature" != "$current_screen_signature" ]; then
      set_agent_state "$pane_id" "$pane_command" 'attention' 'result' "$current_screen_signature"
    elif [ -z "$pane_state" ]; then
      set_agent_state "$pane_id" "$pane_command" 'unknown'
    else
      tmux set-option -pq -t "$pane_id" '@tmux_agents_type' "$pane_command"
    fi
  else
    set_agent_state "$pane_id" "$pane_command" 'unknown'
  fi

  case "$pane_state" in
    attention) attention_count=$((attention_count + 1)) ;;
    running) running_count=$((running_count + 1)) ;;
    unknown) unknown_count=$((unknown_count + 1)) ;;
    stale) stale_count=$((stale_count + 1)) ;;
    *) continue ;;
  esac
  total_count=$((total_count + 1))
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_current_command}')

tmux set-option -gq '@tmux_agents_count_attention' "$attention_count"
tmux set-option -gq '@tmux_agents_count_running' "$running_count"
tmux set-option -gq '@tmux_agents_count_unknown' "$unknown_count"
tmux set-option -gq '@tmux_agents_count_stale' "$stale_count"
tmux set-option -gq '@tmux_agents_count_total' "$total_count"

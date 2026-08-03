#!/usr/bin/env bats

setup() {
  project_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  socket_path="$BATS_TEST_TMPDIR/tmux.sock"
  other_socket_path="$BATS_TEST_TMPDIR/other.sock"

  tmux_test new-session -d -s agents -x 80 -y 24
  tmux_test set-option -g status-right '#{tmux_agents}'
  tmux_test run-shell -b "'$project_root/tmux-agents.tmux'"
  retry_until plugin_path_is_recorded
  pane_id=$(tmux_test display-message -p '#{pane_id}')
}

teardown() {
  tmux_test kill-server >/dev/null 2>&1 || true
  other_tmux_test kill-server >/dev/null 2>&1 || true
}

tmux_test() {
  tmux_on_socket "$socket_path" "$@"
}

other_tmux_test() {
  tmux_on_socket "$other_socket_path" "$@"
}

tmux_on_socket() {
  tmux_socket=$1
  shift
  TMUX='' tmux -S "$tmux_socket" -f /dev/null "$@"
}

mark_pane() {
  mark_pane_on_socket "$socket_path" "$1"
}

mark_pane_on_socket() {
  tmux_on_socket "$1" run-shell -b \
    "TMUX_PANE='$2' '$project_root/scripts/hook.sh' mark"
}

retry_until() {
  attempts=0
  while [ "$attempts" -lt 50 ]; do
    if "$@"; then
      return 0
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  return 1
}

plugin_path_is_recorded() {
  [ "$(tmux_test show-options -gqv '@tmux_agents_plugin_path')" = "$project_root" ]
}

other_plugin_path_is_recorded() {
  [ "$(other_tmux_test show-options -gqv '@tmux_agents_plugin_path')" = "$project_root" ]
}

attention_is_timestamp() {
  attention_marker=$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_attention')
  case "$attention_marker" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

attention_is_clear() {
  [ -z "$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_attention')" ]
}

status_is_hidden() {
  [ -z "$(tmux_test display-message -p '#{E:status-right}')" ]
}

status_is_count() {
  status_is_count_on_socket "$socket_path" "$1"
}

other_status_is_count() {
  status_is_count_on_socket "$other_socket_path" "$1"
}

status_is_count_on_socket() {
  rendered_status=$(tmux_on_socket "$1" show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *"󱙺 $2#[fg="*) return 0 ;;
    *) return 1 ;;
  esac
}

attention_marker_is_replaced() {
  attention_marker=$(tmux_test show-options -pqv -t "$second_pane" \
    '@tmux_agents_attention')
  case "$attention_marker" in
    ''|1|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

@test "loading and marking one pane renders its attention bubble" {
  [ "$(tmux_test show-options -gv '@tmux_agents_plugin_path')" = "$project_root" ]
  [ -z "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_attention')" ]

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' mark"
  retry_until attention_is_timestamp

  rendered_status=$(tmux_test display-message -p '#{E:status-right}')
  case "$rendered_status" in
    *''*'fg=white,bg=red,bold'*'󱙺 1'*'nobold'*''*) ;;
    *) fail "expected one marked pane in status, got: $rendered_status" ;;
  esac
}

@test "clearing one pane hides the bubble and is idempotent" {
  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' mark"
  retry_until attention_is_timestamp

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' clear"
  retry_until attention_is_clear
  retry_until status_is_hidden

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' clear"
  retry_until attention_is_clear
  retry_until status_is_hidden
}

@test "closing a marked pane removes it from the bubble" {
  tmux_test split-window -d -t "$pane_id"
  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' mark"
  retry_until attention_is_timestamp

  tmux_test kill-pane -t "$pane_id"
  retry_until status_is_hidden
}

@test "attention bubble colors follow tmux overrides" {
  tmux_test set-option -g '@tmux_agents_attention_fg' 'blue'
  tmux_test set-option -g '@tmux_agents_attention_bg' 'green'
  tmux_test run-shell -b "'$project_root/tmux-agents.tmux'"

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' mark"
  retry_until attention_is_timestamp

  rendered_status=$(tmux_test show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *'fg=green,bold'*'fg=blue,bg=green,bold'*) ;;
    *) fail "expected configured bubble colors, got: $rendered_status" ;;
  esac
}

@test "counts marked panes once and clearing one preserves the other" {
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")

  mark_pane "$pane_id"
  mark_pane "$second_pane"
  retry_until status_is_count 2

  tmux_test set-option -pq -t "$second_pane" \
    '@tmux_agents_attention' 1
  mark_pane "$second_pane"
  retry_until attention_marker_is_replaced
  retry_until status_is_count 2

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' clear"
  retry_until status_is_count 1

  tmux_test run-shell -b \
    "TMUX_PANE='$second_pane' '$project_root/scripts/hook.sh' clear"
  retry_until status_is_hidden
}

@test "counts marked panes across sessions and removes a closed pane" {
  second_session_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s other)
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")

  mark_pane "$pane_id"
  mark_pane "$second_pane"
  mark_pane "$second_session_pane"
  retry_until status_is_count 3

  tmux_test kill-pane -t "$second_pane"
  retry_until status_is_count 2

  tmux_test kill-session -t other
  tmux_test run-shell -b "'$project_root/scripts/status.sh'"
  retry_until status_is_count 1
}

@test "separate tmux sockets maintain separate attention counts" {
  other_tmux_test new-session -d -s other -x 80 -y 24
  other_tmux_test set-option -g status-right '#{tmux_agents}'
  other_tmux_test run-shell -b "'$project_root/tmux-agents.tmux'"
  retry_until other_plugin_path_is_recorded

  other_pane_id=$(other_tmux_test display-message -p '#{pane_id}')
  mark_pane "$pane_id"
  mark_pane_on_socket "$other_socket_path" "$other_pane_id"
  retry_until status_is_count 1
  retry_until other_status_is_count 1

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' clear"
  retry_until status_is_hidden
  retry_until other_status_is_count 1
}

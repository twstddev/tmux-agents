#!/usr/bin/env bats

setup() {
  project_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  socket_path="$BATS_TEST_TMPDIR/tmux.sock"

  tmux_test new-session -d -s agents -x 80 -y 24
  tmux_test set-option -g status-right '#{tmux_agents}'
  tmux_test run-shell -b "'$project_root/tmux-agents.tmux'"
  retry_until plugin_path_is_recorded
  pane_id=$(tmux_test display-message -p '#{pane_id}')
}

teardown() {
  tmux_test kill-server >/dev/null 2>&1 || true
}

tmux_test() {
  TMUX='' tmux -S "$socket_path" -f /dev/null "$@"
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

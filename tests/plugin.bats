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
  if [ -n "${client2_name-}" ]; then
    tmux_test kill-client -t "$client2_name" >/dev/null 2>&1 || true
  fi
  if [ -n "${client_name-}" ]; then
    tmux_test kill-client -t "$client_name" >/dev/null 2>&1 || true
  fi
  if [ -n "${client2_input-}" ]; then
    exec 8>&- 2>/dev/null || true
  fi
  if [ -n "${client_input-}" ]; then
    exec 9>&- 2>/dev/null || true
  fi
  if [ -n "${client2_pid-}" ]; then
    kill "$client2_pid" >/dev/null 2>&1 || true
  fi
  if [ -n "${client_pid-}" ]; then
    kill "$client_pid" >/dev/null 2>&1 || true
  fi
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

complete_pane() {
  tmux_test run-shell -b \
    "TMUX_PANE='$1' '$project_root/scripts/hook.sh' complete"
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

finished_is_timestamp() {
  finished_pane_is_timestamp "$pane_id"
}

finished_pane_is_timestamp() {
  finished_marker=$(tmux_test show-options -pqv -t "$1" \
    '@tmux_agents_finished')
  case "$finished_marker" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

finished_is_clear() {
  finished_pane_is_clear "$pane_id"
}

finished_pane_is_clear() {
  [ -z "$(tmux_test show-options -pqv -t "$1" \
    '@tmux_agents_finished')" ]
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

finished_status_is_count() {
  rendered_status=$(tmux_test show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *'#[fg=green]󱜚 '"$1"*) return 0 ;;
    *) return 1 ;;
  esac
}

codex_hook() {
  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/plugins/codex/plugins/tmux-agents/scripts/hook.sh' '$1'"
}

claude_hook() {
  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/plugins/claude/plugins/tmux-agents/scripts/hook.sh' '$1'"
}

prefix_a_is_bound() {
  tmux_test list-keys -T prefix a 2>/dev/null |
    grep -F "$project_root/scripts/navigate.sh" >/dev/null
}

client_is_on_pane() {
  [ "$(tmux_test display-message -p -t "$client_name" '#{pane_id}' \
    2>/dev/null)" = "$oldest_pane" ]
}

client_exists() {
  [ -n "$(tmux_test list-clients -F '#{client_name}' 2>/dev/null)" ]
}

start_client() {
  client_input="$BATS_TEST_TMPDIR/client.input"
  mkfifo "$client_input"
  client_output="$BATS_TEST_TMPDIR/client.log"
  script -qefc \
    "TERM=xterm TMUX= tmux -S '$socket_path' -f /dev/null attach-session -t agents" \
    /dev/null <"$client_input" >"$client_output" 2>&1 &
  client_pid=$!
  exec 9>"$client_input"
  if ! retry_until client_exists; then
    sed -n '1,40p' "$client_output"
    false
  fi
  client_name=$(tmux_test list-clients -F '#{client_name}' | head -n 1)
}

start_second_client() {
  start_client_on_session agents
}

start_client_on_session() {
  target_session=$1
  client2_input="$BATS_TEST_TMPDIR/client-2.input"
  mkfifo "$client2_input"
  client2_output="$BATS_TEST_TMPDIR/client-2.log"
  script -qefc \
    "TERM=xterm TMUX= tmux -S '$socket_path' -f /dev/null attach-session -t '$target_session'" \
    /dev/null <"$client2_input" >"$client2_output" 2>&1 &
  client2_pid=$!
  exec 8>"$client2_input"
  retry_until clients_are_attached_twice
  client2_name=$(tmux_test list-clients -F '#{client_name}' |
    grep -v -F "$client_name" | head -n 1)
}

clients_are_attached_twice() {
  [ "$(tmux_test list-clients -F '#{client_name}' | wc -l | tr -d ' ')" -ge 2 ]
}

second_client_is_on_current_pane() {
  [ "$(tmux_test display-message -p -t "$client2_name" '#{pane_id}' \
    2>/dev/null)" = "$pane_id" ]
}

attention_message_is_visible() {
  tmux_test show-messages 2>/dev/null |
    grep -F 'No agents need attention' >/dev/null
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

@test "an unseen completion creates one finished marker and status item" {
  complete_pane "$pane_id"
  retry_until finished_is_timestamp

  rendered_status=$(tmux_test show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *'#[fg=green]󱜚 1'*) ;;
    *) fail "expected one finished item, got: $rendered_status" ;;
  esac
  [ -z "$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_attention')" ]
}

@test "a completion in the selected pane is not finished" {
  start_client

  complete_pane "$pane_id"
  retry_until finished_is_clear
  retry_until status_is_hidden
}

@test "a pane selected by any attached client is not finished" {
  second_session_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s other)
  start_client
  start_client_on_session other

  complete_pane "$second_session_pane"
  retry_until finished_pane_is_clear "$second_session_pane"
  retry_until status_is_hidden
}

@test "an inactive visible split is unseen while the selected pane is seen" {
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")
  tmux_test select-pane -t "$pane_id"

  complete_pane "$second_pane"
  retry_until finished_pane_is_timestamp "$second_pane"
}

@test "duplicate completion preserves the original finished timestamp" {
  complete_pane "$pane_id"
  retry_until finished_is_timestamp
  original_finished=$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_finished')

  complete_pane "$pane_id"
  retry_until finished_is_timestamp
  [ "$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_finished')" = "$original_finished" ]
  retry_until finished_status_is_count 1
}

@test "new activity clears finished state and a new attention request replaces it" {
  complete_pane "$pane_id"
  retry_until finished_is_timestamp

  tmux_test run-shell -b \
    "TMUX_PANE='$pane_id' '$project_root/scripts/hook.sh' clear"
  retry_until finished_is_clear

  complete_pane "$pane_id"
  retry_until finished_is_timestamp
  mark_pane "$pane_id"
  retry_until attention_is_timestamp
  retry_until finished_is_clear
}

@test "background completion clears attention before creating finished state" {
  mark_pane "$pane_id"
  retry_until attention_is_timestamp

  complete_pane "$pane_id"
  retry_until attention_is_clear
  retry_until finished_is_timestamp
}

@test "finished status uses a configurable foreground and stays visually quiet" {
  tmux_test set-option -g '@tmux_agents_finished_fg' 'cyan'
  complete_pane "$pane_id"
  retry_until finished_is_timestamp

  rendered_status=$(tmux_test show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *'#[fg=cyan]󱜚 1'*) ;;
    *) fail "expected configured finished foreground, got: $rendered_status" ;;
  esac
  case "$rendered_status" in
    *'󱜚 1#[bold]'*|*'󱜚 1'*) fail "finished item should not be bold or capped" ;;
  esac
}

@test "attention renders before finished with exactly two spaces" {
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")
  mark_pane "$pane_id"
  complete_pane "$second_pane"
  retry_until finished_pane_is_timestamp "$second_pane"

  rendered_status=$(tmux_test show-options -gqv '@tmux_agents_status')
  case "$rendered_status" in
    *'  #[fg=green]󱜚 1'*) ;;
    *) fail "expected attention followed by two spaces and finished, got: $rendered_status" ;;
  esac
}

@test "finished panes count across sessions and disappear when closed" {
  second_session_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s other)
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")

  complete_pane "$pane_id"
  tmux_test run-shell -b \
    "TMUX_PANE='$second_pane' '$project_root/scripts/hook.sh' complete"
  tmux_test run-shell -b \
    "TMUX_PANE='$second_session_pane' '$project_root/scripts/hook.sh' complete"
  retry_until finished_status_is_count 3

  tmux_test kill-pane -t "$second_pane"
  retry_until finished_status_is_count 2
}

@test "selecting a finished pane acknowledges it without clearing attention" {
  second_pane=$(tmux_test split-window -d -P -F '#{pane_id}' -t "$pane_id")
  complete_pane "$second_pane"
  retry_until finished_pane_is_timestamp "$second_pane"
  mark_pane "$pane_id"
  retry_until attention_is_timestamp

  start_client
  tmux_test select-pane -t "$second_pane"
  retry_until finished_pane_is_clear "$second_pane"
  [ -n "$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_attention')" ]
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

@test "loading binds prefix plus lowercase a to attention navigation" {
  retry_until prefix_a_is_bound
}

@test "navigation reports an empty attention queue without changing the pane" {
  original_pane=$pane_id

  start_client
  tmux_test run-shell -b \
    "'$project_root/scripts/navigate.sh' '$client_name'"
  retry_until attention_message_is_visible

  [ "$(tmux_test display-message -p -t "$client_name" '#{pane_id}')" = \
    "$original_pane" ]
}

@test "navigation selects the oldest marked pane across sessions for its client" {
  oldest_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s oldest)
  mark_pane "$oldest_pane"
  sleep 1
  mark_pane "$pane_id"

  start_client

  printf '\002a' >&9
  retry_until client_is_on_pane

  retry_until status_is_count 2
  [ "$(tmux_test show-options -pqv -t "$oldest_pane" \
    '@tmux_agents_attention')" ]
}

@test "navigation leaves other attached clients in place" {
  oldest_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s oldest)
  mark_pane "$oldest_pane"
  sleep 1
  mark_pane "$pane_id"

  start_client
  start_second_client
  printf '\002a' >&9

  retry_until client_is_on_pane
  retry_until second_client_is_on_current_pane
}

@test "navigation tolerates a marked target vanishing during selection" {
  oldest_pane=$(tmux_test new-session -d -P -F '#{pane_id}' -s oldest)
  mark_pane "$oldest_pane"
  sleep 1
  mark_pane "$pane_id"

  start_client
  tmux_test run-shell -b \
    "PATH='$project_root/tests/fixtures:$PATH' REAL_TMUX='$(command -v tmux)' RACE_TARGET='$oldest_pane' '$project_root/scripts/navigate.sh' '$client_name'"

  if ! retry_until status_is_count 1; then
    tmux_test list-panes -a -F '#{session_name}|#{pane_id}|#{@tmux_agents_attention}'
    tmux_test show-options -gqv '@tmux_agents_status'
    false
  fi
  [ "$(tmux_test display-message -p -t "$client_name" '#{pane_id}')" = \
    "$pane_id" ]
}

@test "Codex marketplace and plugin manifest identify the companion plugin" {
  marketplace="$project_root/plugins/codex/.agents/plugins/marketplace.json"
  manifest="$project_root/plugins/codex/plugins/tmux-agents/.codex-plugin/plugin.json"

  grep -F '"name": "tmux-agents"' "$marketplace"
  grep -F '"path": "./plugins/tmux-agents"' "$marketplace"
  grep -F '"version": "0.1.0"' "$manifest"
  grep -F '"name": "twstd"' "$manifest"
  grep -F '"repository": "https://github.com/twstddev/tmux-agents"' "$manifest"
}

@test "Codex permission hooks delegate mark and later progress to tmux" {
  codex_hook mark
  retry_until attention_is_timestamp
  retry_until status_is_count 1

  codex_hook clear
  retry_until attention_is_clear
  retry_until status_is_hidden
}

@test "Codex stop hook creates finished state through the companion adapter" {
  codex_hook complete
  retry_until finished_is_timestamp
  retry_until attention_is_clear
  retry_until finished_status_is_count 1
}

@test "Codex hook configuration covers permission and progress without structured questions" {
  hooks="$project_root/plugins/codex/plugins/tmux-agents/hooks/hooks.json"

  grep -F '"PermissionRequest": [' "$hooks"
  grep -F '"command": "sh \"${PLUGIN_ROOT}/scripts/hook.sh\" mark"' "$hooks"
  grep -F '"PostToolUse": [' "$hooks"
  grep -F '"UserPromptSubmit": [' "$hooks"
  grep -F '"Stop": [' "$hooks"
  grep -F '"SessionEnd": [' "$hooks"
  clear_command='"command": "sh \"${PLUGIN_ROOT}/scripts/hook.sh\" clear"'
  [ "$(grep -F "$clear_command" "$hooks" | wc -l | tr -d ' ')" -eq 3 ]
  grep -F '"command": "sh \"${PLUGIN_ROOT}/scripts/hook.sh\" complete"' "$hooks"
  ! grep -F 'request_user_input' "$hooks"
}

@test "Codex adapter is silent when tmux or the shared hook is unavailable" {
  run env -u TMUX -u TMUX_PANE \
    "$project_root/plugins/codex/plugins/tmux-agents/scripts/hook.sh" mark
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  tmux_test set-option -g '@tmux_agents_plugin_path' \
    "$BATS_TEST_TMPDIR/missing-tmux-agents"
  codex_hook mark
  sleep 0.1
  attention_is_clear
}

@test "Claude marketplace and plugin manifest identify the companion plugin" {
  marketplace="$project_root/plugins/claude/.claude-plugin/marketplace.json"
  manifest="$project_root/plugins/claude/plugins/tmux-agents/.claude-plugin/plugin.json"

  grep -F '"name": "tmux-agents"' "$marketplace"
  grep -F '"source": "./plugins/tmux-agents"' "$marketplace"
  grep -F '"version": "0.1.0"' "$manifest"
  grep -F '"name": "twstd"' "$manifest"
  grep -F '"repository": "https://github.com/twstddev/tmux-agents"' "$manifest"
}

@test "Claude hooks cover explicit interactions and lifecycle progress" {
  hooks="$project_root/plugins/claude/plugins/tmux-agents/hooks/hooks.json"

  grep -F '"PermissionRequest": [' "$hooks"
  grep -F '"PreToolUse": [' "$hooks"
  grep -F '"matcher": "AskUserQuestion"' "$hooks"
  grep -F '"matcher": "ExitPlanMode"' "$hooks"
  grep -F '"Elicitation": [' "$hooks"
  grep -F '"ElicitationResult": [' "$hooks"
  grep -F '"PostToolUse": [' "$hooks"
  grep -F '"PostToolUseFailure": [' "$hooks"
  grep -F '"Stop": [' "$hooks"
  grep -F '"UserPromptSubmit": [' "$hooks"
  grep -F '"SessionEnd": [' "$hooks"

  mark_command='"command": "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh\" mark"'
  clear_command='"command": "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh\" clear"'
  grep -A 6 '"matcher": "AskUserQuestion"' "$hooks" |
    grep -F "$mark_command"
  grep -A 6 '"matcher": "ExitPlanMode"' "$hooks" |
    grep -F "$mark_command"
  [ "$(grep -F "$mark_command" "$hooks" | wc -l | tr -d ' ')" -eq 4 ]
  [ "$(grep -F "$clear_command" "$hooks" | wc -l | tr -d ' ')" -eq 5 ]
  grep -F '"command": "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh\" complete"' "$hooks"
}

@test "Claude interaction hooks delegate mark and progress to tmux" {
  claude_hook mark
  retry_until attention_is_timestamp
  retry_until status_is_count 1

  claude_hook clear
  retry_until attention_is_clear
  retry_until status_is_hidden
}

@test "Claude stop hook creates finished state through the companion adapter" {
  claude_hook complete
  retry_until finished_is_timestamp
  retry_until finished_status_is_count 1
}

@test "Claude adapter is silent when tmux or the shared hook is unavailable" {
  run env -u TMUX -u TMUX_PANE \
    "$project_root/plugins/claude/plugins/tmux-agents/scripts/hook.sh" mark
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  tmux_test set-option -g '@tmux_agents_plugin_path' \
    "$BATS_TEST_TMPDIR/missing-tmux-agents"
  claude_hook mark
  sleep 0.1
  attention_is_clear
}

@test "runtime scripts parse with a POSIX shell" {
  for runtime_script in \
    "$project_root/tmux-agents.tmux" \
    "$project_root/scripts/hook.sh" \
    "$project_root/scripts/navigate.sh" \
    "$project_root/scripts/status.sh" \
    "$project_root/plugins/codex/plugins/tmux-agents/scripts/hook.sh" \
    "$project_root/plugins/claude/plugins/tmux-agents/scripts/hook.sh"; do
    run sh -n "$runtime_script"
    [ "$status" -eq 0 ]
  done
}

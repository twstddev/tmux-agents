#!/usr/bin/env bats

setup() {
  project_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  socket_path="$BATS_TEST_TMPDIR/tmux.sock"
  test_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$test_bin"
  cp "$(command -v bash)" "$test_bin/codex"
  cp "$(command -v bash)" "$test_bin/claude"
  cp "$project_root/tests/helpers/fzf" "$test_bin/fzf"
  cp "$project_root/tests/helpers/tmux" "$test_bin/tmux"
  chmod +x "$test_bin/fzf" "$test_bin/tmux"

  tmux_test new-session -d -s agents -x 80 -y 24
  tmux_test set-option -g remain-on-exit on
}

teardown() {
  tmux_test kill-server >/dev/null 2>&1 || true
  if [ -n "${status_client_pid:-}" ]; then
    exec 9>&-
    wait "$status_client_pid" >/dev/null 2>&1 || true
  fi
  if [ -n "${observer_client_pid:-}" ]; then
    exec 8>&-
    wait "$observer_client_pid" >/dev/null 2>&1 || true
  fi
}

tmux_test() {
  TMUX='' tmux -S "$socket_path" -f /dev/null "$@"
}

plugin_option() {
  tmux_test show-options -gv "$1"
}

plugin_option_is() {
  option_name=$1
  expected=$2

  [ "$(plugin_option "$option_name")" = "$expected" ]
}

state_counts_sum_to_total() {
  attention=$(plugin_option '@tmux_agents_count_attention')
  running=$(plugin_option '@tmux_agents_count_running')
  unknown=$(plugin_option '@tmux_agents_count_unknown')
  stale=$(plugin_option '@tmux_agents_count_stale')
  total=$(plugin_option '@tmux_agents_count_total')

  [ "$((attention + running + unknown + stale))" -eq "$total" ]
}

retry_until() {
  max_attempts=$1
  shift
  attempts=0

  while [ "$attempts" -lt "$max_attempts" ]; do
    if "$@"; then
      return 0
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done

  return 1
}

status_right_contains() {
  expected=$1
  rendered_status=$(tmux_test display-message -p '#{E:status-right}')
  case "$rendered_status" in
    *"$expected"*) return 0 ;;
  esac

  return 1
}

pane_current_command_is() {
  target=$1
  expected=$2

  [ "$(tmux_test display-message -p -t "$target" '#{pane_current_command}')" = "$expected" ]
}

status_client_is_attached() {
  [ -n "$(tmux_test list-clients -F '#{client_name}')" ]
}

two_clients_are_attached() {
  [ "$(tmux_test list-clients -F '#{client_name}' | wc -l | tr -d ' ')" -eq 2 ]
}

spawn_attached_client() {
  input_fd=$1

  case "$(uname -s)" in
    Darwin)
      script -q /dev/null env TMUX= TERM=xterm-256color \
        tmux -S "$socket_path" -f /dev/null attach-session -t agents \
        <&"$input_fd" >/dev/null 2>&1 &
      ;;
    *)
      script -q -c \
        "env TMUX= TERM=xterm-256color tmux -S '$socket_path' -f /dev/null attach-session -t agents" \
        /dev/null <&"$input_fd" >/dev/null 2>&1 &
      ;;
  esac
  attached_client_pid=$!
}

attach_status_client() {
  status_client_pipe="$BATS_TEST_TMPDIR/status-client.pipe"
  mkfifo "$status_client_pipe"
  exec 9<>"$status_client_pipe"

  spawn_attached_client 9
  status_client_pid=$attached_client_pid

  retry_until 50 status_client_is_attached
  status_client_name=$(tmux_test list-clients -F '#{client_name}')
}

attach_observer_client() {
  observer_client_pipe="$BATS_TEST_TMPDIR/observer-client.pipe"
  mkfifo "$observer_client_pipe"
  exec 8<>"$observer_client_pipe"

  spawn_attached_client 8
  observer_client_pid=$attached_client_pid

  retry_until 50 two_clients_are_attached
  while IFS= read -r client_name; do
    if [ "$client_name" != "$status_client_name" ]; then
      observer_client_name=$client_name
    fi
  done < <(tmux_test list-clients -F '#{client_name}')
}

client_target() {
  client_name=$1

  while IFS='|' read -r listed_client listed_target; do
    if [ "$listed_client" = "$client_name" ]; then
      printf '%s\n' "$listed_target"
      return
    fi
  done < <(
    tmux_test list-clients \
      -F '#{client_name}|#{session_id}:#{window_id}.#{pane_id}'
  )

  return 1
}

client_target_is() {
  client_name=$1
  expected_target=$2

  [ "$(client_target "$client_name")" = "$expected_target" ]
}

pane_state_is() {
  pane_id=$1
  expected_state=$2

  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_state')" = "$expected_state" ]
}

enable_fzf_stub() {
  chooser_input="$BATS_TEST_TMPDIR/chooser-input"
  chooser_args="$BATS_TEST_TMPDIR/chooser-args"
  chooser_done="$BATS_TEST_TMPDIR/chooser-done"
  chooser_initial="$BATS_TEST_TMPDIR/chooser-initial"
  chooser_preview="$BATS_TEST_TMPDIR/chooser-preview"
  chooser_started="$BATS_TEST_TMPDIR/chooser-started"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$(command -v tmux)"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_INPUT "$chooser_input"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_ARGS "$chooser_args"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_DONE "$chooser_done"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_INITIAL "$chooser_initial"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_PREVIEW "$chooser_preview"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_STARTED "$chooser_started"
}

enable_slow_initial_scan() {
  initial_scan_started="$BATS_TEST_TMPDIR/initial-scan-started"
  initial_scan_done="$BATS_TEST_TMPDIR/initial-scan-done"
  tmux_test set-environment -g \
    TMUX_AGENTS_TEST_INITIAL_SCAN_STARTED "$initial_scan_started"
  tmux_test set-environment -g \
    TMUX_AGENTS_TEST_INITIAL_SCAN_DONE "$initial_scan_done"
  tmux_test set-environment -g TMUX_AGENTS_TEST_SCAN_DELAY 1
}

initial_scan_has_started() {
  [ -f "$initial_scan_started" ]
}

enable_slow_post_selection_scan() {
  post_switch_marker="$BATS_TEST_TMPDIR/post-switch"
  tmux_test set-environment -g TMUX_AGENTS_TEST_POST_SWITCH "$post_switch_marker"
  tmux_test set-environment -g TMUX_AGENTS_TEST_SCAN_DELAY 1
}

selection_has_switched() {
  [ -f "$post_switch_marker" ]
}

client_accepts_new_window() {
  printf '\002c' >&9
  sleep 0.02
  [ "$(tmux_test list-windows -t other -F '#{window_id}' | wc -l | tr -d ' ')" -gt 1 ]
}

chooser_input_is_ready() {
  [ -f "$chooser_done" ]
}

open_chooser() {
  chooser_key=${1:-A}
  printf '\002%s' "$chooser_key" >&9
  retry_until 100 chooser_input_is_ready
}

load_plugin() {
  target=${1:-agents:0.0}
  tmux_test run-shell -t "$target" "$project_root/tmux-agents.tmux '#{pane_id}'"
}

show_idle_agent() {
  target=$1
  agent_type=$2
  tmux_test respawn-pane -k -t "$target" \
    "$project_root/tests/fixtures/show-$agent_type-idle.sh '$test_bin/$agent_type'"

  retry_until 50 pane_current_command_is "$target" "$agent_type"
}

show_idle_codex() {
  show_idle_agent "$1" codex
}

show_idle_claude() {
  show_idle_agent "$1" claude
}

show_running_agent() {
  target=$1
  agent_type=$2
  tmux_test respawn-pane -k -t "$target" \
    "$project_root/tests/fixtures/show-$agent_type-running.sh '$test_bin/$agent_type'"

  retry_until 50 pane_current_command_is "$target" "$agent_type"
}

show_running_codex() {
  show_running_agent "$1" codex
}

show_running_claude() {
  show_running_agent "$1" claude
}

show_agent_screen() {
  target=$1
  agent_type=$2
  screen_type=$3
  tmux_test respawn-pane -k -t "$target" \
    "$project_root/tests/fixtures/show-$agent_type-$screen_type.sh '$test_bin/$agent_type'"

  retry_until 50 pane_current_command_is "$target" "$agent_type"
}

show_codex_approval() {
  show_agent_screen "$1" codex approval
}

show_claude_approval() {
  show_agent_screen "$1" claude approval
}

show_codex_question() {
  show_agent_screen "$1" codex question
}

show_claude_question() {
  show_agent_screen "$1" claude question
}

show_codex_result() {
  show_agent_screen "$1" codex result
}

show_claude_result() {
  show_agent_screen "$1" claude result
}

show_unsupported_agent() {
  target=$1
  agent_type=$2
  tmux_test respawn-pane -k -t "$target" \
    "$project_root/tests/fixtures/show-unsupported.sh '$test_bin/$agent_type'"

  retry_until 50 pane_current_command_is "$target" "$agent_type"
}

@test "loading the plugin is idempotent and leaves status placement alone" {
  tmux_test set-option -g status-left 'left-side'
  tmux_test set-option -g status-right 'right-side'

  load_plugin
  load_plugin

  [ "$(tmux_test show-options -gv status-left)" = 'left-side' ]
  [ "$(tmux_test show-options -gv status-right)" = 'right-side' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "a selected idle Codex Agent is Stale and counted" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0
  show_idle_codex agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
  retry_until 100 status_right_contains '󰚩 #[fg=colour220]1 #[fg=colour244]1'
  [ "$(tmux_test show-options -pqv -t agents:background.0 '@tmux_agents_state')" = 'unknown' ]

  runtime_options=$(tmux_test show-options -g)
  runtime_options="$runtime_options$(tmux_test show-options -w -t agents:0.0)"
  runtime_options="$runtime_options$(tmux_test show-options -p -t agents:0.0)"
  case "$runtime_options" in
    *'Ask Codex to do anything'*|*'100% left'*) false ;;
  esac
  [ -z "$(tmux_test show-options -gqv '@tmux_agents_state')" ]
  [ -z "$(tmux_test show-options -wqv -t agents:0.0 '@tmux_agents_state')" ]

  tmux_test split-window -d -t agents:0.0
  tmux_test select-pane -t agents:0.1
  load_plugin agents:0.1

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
}

@test "a first-discovered background idle Codex Agent is Unknown" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:background.0 '@tmux_agents_state')" = 'unknown' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "recognized Codex and Claude Code work is Running and counted" {
  tmux_test new-window -d -t agents: -n codex-agent
  tmux_test new-session -d -s other -x 80 -y 24
  show_running_codex agents:codex-agent.0
  show_running_claude other:0.0

  load_plugin agents:0.0

  sleep 0.05
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:codex-agent.0 '@tmux_agents_state')" = 'running' ]
  [ "$(tmux_test show-options -pv -t other:0.0 '@tmux_agents_state')" = 'running' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
}

@test "a supported Codex approval Needs attention" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]

  runtime_options=$(tmux_test show-options -p -t agents:input.0)
  case "$runtime_options" in
    *'Would you like to run'*|*'git status --short'*) false ;;
  esac
}

@test "a supported Claude Code approval Needs attention" {
  tmux_test new-window -d -t agents: -n input
  show_claude_approval agents:input.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a supported Codex question Needs attention" {
  tmux_test new-window -d -t agents: -n input
  show_codex_question agents:input.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a supported Claude Code question Needs attention" {
  tmux_test new-window -d -t agents: -n input
  show_claude_question agents:input.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a Codex Agent that finishes in the background Needs attention" {
  tmux_test new-window -d -t agents: -n reviewable
  show_running_codex agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'running' ]

  show_codex_result agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]

  attention_since=$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state_since')
  case "$attention_since" in
    ''|*[!0-9]*) false ;;
  esac

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state_since')" = "$attention_since" ]
}

@test "a Claude Code Agent that finishes in the background Needs attention" {
  tmux_test new-window -d -t agents: -n reviewable
  show_running_claude agents:reviewable.0
  load_plugin agents:0.0

  show_claude_result agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a Running Agent that finishes while selected becomes Stale" {
  show_running_codex agents:0.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'running' ]
  state_counts_sum_to_total

  show_codex_result agents:0.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  state_counts_sum_to_total
}

@test "ordinary pane selection acknowledges a Reviewable result as Stale" {
  tmux_test new-window -d -t agents: -n reviewable
  show_running_claude agents:reviewable.0
  load_plugin agents:0.0
  show_claude_result agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'attention' ]
  state_counts_sum_to_total

  tmux_test select-window -t agents:reviewable
  load_plugin agents:reviewable.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  state_counts_sum_to_total
}

@test "an unresolved Input request returns to Needs attention after deselection" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  state_counts_sum_to_total
  attention_since=$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')

  tmux_test select-window -t agents:input
  load_plugin agents:input.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')" = "$attention_since" ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  state_counts_sum_to_total

  while [ "$(date +%s)" -le "$attention_since" ]; do
    sleep 0.02
  done

  tmux_test select-window -t agents:0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')" -gt "$attention_since" ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  state_counts_sum_to_total

  show_running_codex agents:input.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'running' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]
  state_counts_sum_to_total
}

@test "a new Input request resets its oldest-waiting age" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0
  load_plugin agents:0.0

  tmux_test set-option -pq -t agents:input.0 '@tmux_agents_state_since' 1
  show_codex_question agents:input.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')" != '1' ]
}

@test "a fast Input response becomes a new background Reviewable result" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0
  load_plugin agents:0.0

  tmux_test select-window -t agents:input
  load_plugin agents:input.0
  tmux_test set-option -pq -t agents:input.0 '@tmux_agents_state_since' 1

  show_codex_result agents:input.0
  tmux_test select-window -t agents:0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_attention_evidence')" = 'result' ]
  [ -z "$(tmux_test show-options -pqv -t agents:input.0 '@tmux_agents_acknowledged_signature')" ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')" != '1' ]
}

@test "an unsupported Agent screen is Unknown" {
  show_unsupported_agent agents:0.0 codex

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_type')" = 'codex' ]
  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'unknown' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "Codex and Claude Code are discovered across sessions while shells are ignored" {
  tmux_test new-window -d -t agents: -n codex-agent
  tmux_test new-session -d -s other -x 80 -y 24
  show_idle_codex agents:codex-agent.0
  show_idle_claude other:0.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:codex-agent.0 '@tmux_agents_type')" = 'codex' ]
  [ "$(tmux_test show-options -pv -t other:0.0 '@tmux_agents_type')" = 'claude' ]
  [ "$(tmux_test show-options -pv -t agents:codex-agent.0 '@tmux_agents_state')" = 'unknown' ]
  [ "$(tmux_test show-options -pv -t other:0.0 '@tmux_agents_state')" = 'unknown' ]
  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_type')" ]
  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_state')" ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
}

@test "selecting an Unknown idle Agent acknowledges it as Stale" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:background.0 '@tmux_agents_state')" = 'unknown' ]

  tmux_test select-window -t agents:background
  load_plugin agents:background.0

  [ "$(tmux_test show-options -pv -t agents:background.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "closing an Agent pane removes it from the counts" {
  tmux_test new-window -d -t agents: -n background
  show_idle_claude agents:background.0
  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_unknown')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]

  tmux_test kill-pane -t agents:background.0
  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_unknown')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "the default widget shows nonzero Unknown before Stale" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0
  show_idle_claude agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin agents:0.0

  retry_until 100 status_right_contains '#[fg=colour220]1 #[fg=colour244]1'
}

@test "the default widget shows nonzero Running in green before Unknown and Stale" {
  tmux_test new-window -d -t agents: -n running
  tmux_test new-window -d -t agents: -n unknown
  show_running_codex agents:running.0
  show_unsupported_agent agents:unknown.0 claude
  show_idle_codex agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin agents:0.0

  retry_until 100 status_right_contains '#[fg=colour40]1 #[fg=colour220]1 #[fg=colour244]1'
}

@test "the default widget shows nonzero Needs attention first in an orange pill" {
  tmux_test new-window -d -t agents: -n running
  tmux_test new-window -d -t agents: -n input
  show_running_codex agents:running.0
  show_codex_approval agents:input.0
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin agents:0.0

  retry_until 100 status_right_contains \
    '󰚩 #[fg=colour208]#[fg=colour232,bg=colour208]1#[fg=colour208,bg=default] #[fg=colour40]1 #[fg=colour244]0'
}

@test "status retains its prior rendering while 25 Agents scan asynchronously" {
  tmux_test set-option -g status-interval 0
  tmux_test set-option -g status off
  tmux_test set-option -g status-right '#{tmux_agents}'
  load_plugin agents:0.0
  attach_status_client

  index=1
  while [ "$index" -le 25 ]; do
    tmux_test new-window -d -t agents: -n "running-$index"
    show_running_codex "agents:running-$index.0"
    index=$((index + 1))
  done

  tmux_test set-option -g status-interval 2
  tmux_test set-option -g status on
  rendered_status=$(tmux_test display-message -p '#{E:status-right}')

  case "$rendered_status" in
    *'󰚩 0'*) ;;
    *) false ;;
  esac
  [ "$(tmux_test display-message -p '#{session_name}')" = 'agents' ]
  retry_until 100 plugin_option_is '@tmux_agents_count_running' '25'
  retry_until 100 plugin_option_is '@tmux_agents_count_total' '25'
  retry_until 100 status_right_contains '#[fg=colour40]25'
}

@test "the explicit default placeholder renders the robot and Stale zero" {
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin

  retry_until 100 status_right_contains '#[fg=colour244]󰚩 0#[default]'
  installed_status=$(tmux_test show-options -gv status-right)
  load_plugin
  [ "$(tmux_test show-options -gv status-right)" = "$installed_status" ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "the chooser groups Agents with useful context and a live screen preview" {
  tmux_test new-window -d -t agents: -n older-attention
  tmux_test new-window -d -t agents: -n newer-attention
  tmux_test new-window -d -t agents: -n stale
  tmux_test new-window -d -t agents: -n unknown
  tmux_test new-window -d -t agents: -n running
  show_codex_approval agents:older-attention.0
  show_claude_approval agents:newer-attention.0
  show_idle_claude agents:stale.0
  show_idle_codex agents:unknown.0
  show_running_claude agents:running.0

  tmux_test select-window -t agents:stale
  load_plugin agents:stale.0
  tmux_test select-window -t agents:0
  load_plugin agents:0.0

  tmux_test set-option -pq -t agents:older-attention.0 '@tmux_agents_state_since' 10
  tmux_test set-option -pq -t agents:newer-attention.0 '@tmux_agents_state_since' 20
  tmux_test select-pane -t agents:older-attention.0 -T 'Old review'
  tmux_test select-pane -t agents:newer-attention.0 -T 'New approval'
  tmux_test select-pane -t agents:stale.0 -T 'claude'
  tmux_test select-pane -t agents:unknown.0 -T ''
  tmux_test select-pane -t agents:running.0 -T 'Index the docs'

  older_id=$(tmux_test display-message -p -t agents:older-attention.0 '#{pane_id}')
  newer_id=$(tmux_test display-message -p -t agents:newer-attention.0 '#{pane_id}')
  stale_id=$(tmux_test display-message -p -t agents:stale.0 '#{pane_id}')
  unknown_id=$(tmux_test display-message -p -t agents:unknown.0 '#{pane_id}')
  running_id=$(tmux_test display-message -p -t agents:running.0 '#{pane_id}')

  enable_fzf_stub
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  expected_order=$(printf '%s\n' \
    "$older_id" "$newer_id" "$stale_id" "$unknown_id" "$running_id")
  actual_order=$(cut -f1 "$chooser_input")
  [ "$actual_order" = "$expected_order" ]

  chooser_items=$(<"$chooser_input")
  case "$chooser_items" in
    *"$older_id	Old review | Needs attention · Codex · agents:older-attention.0 · "*" · "*[smhd]) ;;
    *) false ;;
  esac
  case "$chooser_items" in
    *"$stale_id	claude |"*) false ;;
  esac
  case "$chooser_items" in
    *"$unknown_id	Unknown · Codex · agents:unknown.0 · "*) ;;
    *) false ;;
  esac
  case "$chooser_items" in
    *"$running_id	Index the docs | Running · Claude Code · agents:running.0 · "*) ;;
    *) false ;;
  esac
  case "$(<"$chooser_preview")" in
    *'Press enter to confirm or esc to cancel'*) ;;
    *) false ;;
  esac

  chooser_options=$(<"$chooser_args")
  case "$chooser_options" in
    *'--preview'*'tmux capture-pane -p -e -t {1}'*) ;;
    *) false ;;
  esac
  case "$chooser_options" in
    *'--preview-window=right,60%,wrap'*) ;;
    *) false ;;
  esac
  case "$chooser_options" in
    *'--no-sort'*) false ;;
  esac
  case "$chooser_options" in
    *'--tmux=center,80%,80%'*) ;;
    *) false ;;
  esac
  case "$chooser_options" in
    *'--height='*|*'border-native'*) false ;;
  esac

  chooser_binding=$(tmux_test list-keys -T prefix A)
  case "$chooser_binding" in
    *'display-popup'*) false ;;
  esac
}

@test "chooser selection switches only its client and acknowledges the Agent" {
  tmux_test new-session -d -s other -n decoy -x 80 -y 24
  tmux_test new-window -d -t other: -n target
  tmux_test split-window -d -t other:target.0
  tmux_test select-pane -t other:target.0
  tmux_test select-window -t other:decoy
  show_running_codex other:target.1
  load_plugin agents:0.0
  show_codex_result other:target.1
  load_plugin agents:0.0

  target_id=$(tmux_test display-message -p -t other:target.1 '#{pane_id}')
  target_location=$(tmux_test display-message -p -t "$target_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  [ "$(tmux_test show-options -pv -t "$target_id" '@tmux_agents_state')" = 'attention' ]

  enable_fzf_stub
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_SELECTION "$target_id"
  attach_status_client
  attach_observer_client
  observer_target=$(client_target "$observer_client_name")
  load_plugin agents:0.0
  open_chooser

  retry_until 100 client_target_is "$status_client_name" "$target_location"
  client_target_is "$observer_client_name" "$observer_target"
  retry_until 100 pane_state_is "$target_id" stale
}

@test "the chooser prefix binding is configurable" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0
  tmux_test set-option -g '@tmux_agents_chooser_key' G

  enable_fzf_stub
  attach_status_client
  load_plugin agents:0.0
  open_chooser G

  [ -s "$chooser_input" ]
}

@test "chooser closes before selected Agent state refresh completes" {
  tmux_test new-session -d -s other -n target -x 80 -y 24
  show_idle_codex other:target.0
  load_plugin agents:0.0

  target_id=$(tmux_test display-message -p -t other:target.0 '#{pane_id}')
  [ "$(tmux_test show-options -pv -t "$target_id" '@tmux_agents_state')" = 'unknown' ]

  enable_fzf_stub
  enable_slow_post_selection_scan
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_SELECTION "$target_id"
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  retry_until 100 selection_has_switched
  retry_until 20 client_accepts_new_window
  retry_until 100 pane_state_is "$target_id" stale
}

@test "chooser opens with a loading row before its fresh scan completes" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0
  load_plugin agents:0.0

  enable_fzf_stub
  enable_slow_initial_scan
  attach_status_client
  printf '\002A' >&9

  retry_until 100 initial_scan_has_started
  [ -f "$chooser_started" ]
  [ ! -f "$initial_scan_done" ]
  case "$(<"$chooser_initial")" in
    *'Loading Agents…'*) ;;
    *) false ;;
  esac
  retry_until 100 chooser_input_is_ready
}

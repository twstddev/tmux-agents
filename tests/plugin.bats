#!/usr/bin/env bats

setup() {
  project_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  real_tmux=$(command -v tmux)
  real_awk=$(command -v awk)
  socket_path="$BATS_TEST_TMPDIR/tmux.sock"
  test_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$test_bin"
  cp "$(command -v bash)" "$test_bin/codex"
  cp "$(command -v bash)" "$test_bin/claude"
  cp "$project_root/tests/helpers/ps" "$test_bin/ps"
  cp "$project_root/tests/helpers/fzf" "$test_bin/fzf"
  cp "$project_root/tests/helpers/nvim" "$test_bin/nvim"
  cp "$project_root/tests/helpers/tmux" "$test_bin/tmux"
  cp "$project_root/tests/helpers/awk" "$test_bin/awk"
  chmod +x "$test_bin/ps" "$test_bin/fzf" "$test_bin/nvim" "$test_bin/tmux" \
    "$test_bin/awk"

  tmux_test new-session -d -s agents -x 80 -y 24
  tmux_test set-option -g remain-on-exit on
  tmux_test set-option -g @tmux_agents_hook_grace_seconds 0
}

teardown() {
  if [ -n "${capture_release-}" ]; then
    : >"$capture_release"
  fi
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
  stale=$(plugin_option '@tmux_agents_count_stale')
  total=$(plugin_option '@tmux_agents_count_total')

  [ "$((attention + running + stale))" -eq "$total" ]
}

all_runtime_options() {
  target=$1

  tmux_test show-options -g
  tmux_test show-options -w -t "$target"
  tmux_test show-options -p -t "$target"
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

client_written() {
  client_name=$1

  while IFS='|' read -r listed_client written_bytes; do
    if [ "$listed_client" = "$client_name" ]; then
      printf '%s\n' "$written_bytes"
      return
    fi
  done < <(tmux_test list-clients -F '#{client_name}|#{client_written}')

  return 1
}

client_has_written_since() {
  client_name=$1
  previous_written=$2

  [ "$(client_written "$client_name")" -gt "$previous_written" ]
}

pane_state_is() {
  pane_id=$1
  expected_state=$2

  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_state')" = "$expected_state" ]
}

pane_attention_is_acknowledged() {
  target=$1

  [ "$(tmux_test show-options -pqv -t "$target" \
    '@tmux_agents_acknowledged_signature')" = \
    "$(tmux_test show-options -pqv -t "$target" \
      '@tmux_agents_attention_signature')" ]
}

client_messages_contain() {
  client_name=$1
  expected=$2

  case "$(tmux_test show-messages -t "$client_name")" in
    *"$expected"*) return 0 ;;
  esac

  return 1
}

sidekick_show_was_requested() {
  grep -Fq "sidekick.cli').show" "$nvim_args"
}

enable_fzf_stub() {
  chooser_input="$BATS_TEST_TMPDIR/chooser-input"
  chooser_args="$BATS_TEST_TMPDIR/chooser-args"
  chooser_done="$BATS_TEST_TMPDIR/chooser-done"
  chooser_initial="$BATS_TEST_TMPDIR/chooser-initial"
  chooser_preview="$BATS_TEST_TMPDIR/chooser-preview"
  chooser_started="$BATS_TEST_TMPDIR/chooser-started"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$real_tmux"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_INPUT "$chooser_input"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_ARGS "$chooser_args"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_DONE "$chooser_done"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_INITIAL "$chooser_initial"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_PREVIEW "$chooser_preview"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_STARTED "$chooser_started"
}

enable_nvim_stub() {
  nvim_args="$BATS_TEST_TMPDIR/nvim-args"
  nvim_response="$BATS_TEST_TMPDIR/nvim-response"
  printf '%s\n' 1 >"$nvim_response"
  : >"$nvim_args"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export PATH="$test_bin:$PATH"
  export TMUX_AGENTS_TEST_NVIM_ARGS="$nvim_args"
  export TMUX_AGENTS_TEST_NVIM_RESPONSE="$nvim_response"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_NVIM_ARGS "$nvim_args"
  tmux_test set-environment -g TMUX_AGENTS_TEST_NVIM_RESPONSE "$nvim_response"
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

show_host_process() {
  target=$1

  tmux_test respawn-pane -k -t "$target" \
    "$project_root/tests/fixtures/show-unsupported.sh '$(command -v bash)'"

  retry_until 50 pane_current_command_is "$target" bash
}

enable_process_snapshot() {
  process_snapshot="$BATS_TEST_TMPDIR/process-snapshot"
  process_snapshot_count="$BATS_TEST_TMPDIR/process-snapshot-count"
  process_environment="$BATS_TEST_TMPDIR/process-environment"
  process_environment_count="$BATS_TEST_TMPDIR/process-environment-count"
  : >"$process_environment"
  printf '%s\n' 0 >"$process_environment_count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_REAL_AWK="$real_awk"
  export TMUX_AGENTS_TEST_PROCESS_SNAPSHOT="$process_snapshot"
  export TMUX_AGENTS_TEST_PROCESS_SNAPSHOT_COUNT="$process_snapshot_count"
  export TMUX_AGENTS_TEST_PROCESS_ENVIRONMENT="$process_environment"
  export TMUX_AGENTS_TEST_PROCESS_ENVIRONMENT_COUNT="$process_environment_count"
  export PATH="$test_bin:$PATH"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_AWK "$TMUX_AGENTS_TEST_REAL_AWK"
  tmux_test set-environment -g TMUX_AGENTS_TEST_PROCESS_SNAPSHOT "$process_snapshot"
  tmux_test set-environment -g TMUX_AGENTS_TEST_PROCESS_SNAPSHOT_COUNT "$process_snapshot_count"
  tmux_test set-environment -g TMUX_AGENTS_TEST_PROCESS_ENVIRONMENT "$process_environment"
  tmux_test set-environment -g TMUX_AGENTS_TEST_PROCESS_ENVIRONMENT_COUNT \
    "$process_environment_count"
}

enable_tmux_command_log() {
  tmux_command_log="$BATS_TEST_TMPDIR/tmux-command-log"
  : >"$tmux_command_log"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_COMMAND_LOG="$tmux_command_log"
  export PATH="$test_bin:$PATH"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$real_tmux"
  tmux_test set-environment -g TMUX_AGENTS_TEST_COMMAND_LOG "$tmux_command_log"
}

record_passive_codex() {
  target=$1
  pane_id=$(tmux_test display-message -p -t "$target" '#{pane_id}')
  pane_pid=$(pane_process_id "$target")
  tmux_test set-option -pq -t "$target" '@tmux_agents_type' codex
  tmux_test set-option -pq -t "$target" '@tmux_agents_identity' "pid:$pane_pid"
  tmux_test set-option -pq -t "$target" '@tmux_agents_process_identity' "pid:$pane_pid"
  tmux_test set-option -pq -t "$target" '@tmux_agents_state_source' passive
  tmux_test set-option -pq -t "$target" '@tmux_agents_state' stale
  tmux_test set-option -pq -t "$target" '@tmux_agents_state_since' 1
}

set_process_snapshot() {
  printf '%s\n' "$@" >"$process_snapshot"
}

set_process_environment() {
  printf '%s\n' "$@" >"$process_environment"
}

pane_process_id() {
  tmux_test display-message -p -t "$1" '#{pane_pid}'
}

send_hook_event() {
  target=$1
  agent_type=$2
  event_name=$3
  session_id=$4
  turn_id=${5:-turn-1}
  pane_id=$(tmux_test display-message -p -t "$target" '#{pane_id}')
  server_pid=$(tmux_test display-message -p -t "$target" '#{pid}')

  if [ -n "${TMUX_AGENTS_TEST_REFRESH_COUNT-}" ] ||
    [ -n "${TMUX_AGENTS_TEST_SET_OPTION_COUNT-}" ] ||
    [ -n "${TMUX_AGENTS_TEST_PROCESS_SNAPSHOT-}" ] ||
    [ -n "${TMUX_AGENTS_TEST_NVIM_ARGS-}" ]; then
    printf '%s\n' "{\"session_id\":\"$session_id\",\"turn_id\":\"$turn_id\"}" |
      PATH="$test_bin:$PATH" TMUX="$socket_path,$server_pid,0" TMUX_PANE="$pane_id" \
        NVIM="${6-}" "$project_root/scripts/hook.sh" "$agent_type" "$event_name"
  else
    printf '%s\n' "{\"session_id\":\"$session_id\",\"turn_id\":\"$turn_id\"}" |
      TMUX="$socket_path,$server_pid,0" TMUX_PANE="$pane_id" \
        NVIM="${6-}" "$project_root/scripts/hook.sh" "$agent_type" "$event_name"
  fi
}

run_diagnostics() {
  server_pid=$(tmux_test display-message -p '#{pid}')
  TMUX="$socket_path,$server_pid,0" "$project_root/scripts/diagnose.sh"
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
  [ "$(plugin_option '@tmux_agents_count_stale')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "loading the plugin preserves existing tmux hooks" {
  existing_hook='set-option -g @tmux_agents_test_existing_hook 1'
  tmux_test set-hook -g after-select-pane "$existing_hook"
  tmux_test set-hook -g after-select-window "$existing_hook"
  tmux_test set-hook -g pane-exited "$existing_hook"

  load_plugin

  case "$(tmux_test show-hooks -g after-select-pane)" in
    *"$existing_hook"*selection.sh*) ;;
    *) false ;;
  esac
  case "$(tmux_test show-hooks -g after-select-window)" in
    *"$existing_hook"*selection.sh*) ;;
    *) false ;;
  esac
  case "$(tmux_test show-hooks -g pane-exited)" in
    *"$existing_hook"*lifecycle.sh*) ;;
    *) false ;;
  esac
}

@test "a session-start hook registers a standalone Codex Agent as Stale" {
  load_plugin

  send_hook_event agents:0.0 codex start codex-session-1

  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a hook verifies an embedded Sidekick Agent before recording its host" {
  enable_nvim_stub
  load_plugin

  send_hook_event agents:0.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick

  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_type')" = 'codex' ]
  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_identity')" = \
    'sidekick-session-1' ]
  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_host')" = 'sidekick' ]
  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_nvim_server')" = \
    '/tmp/nvim-sidekick' ]

  case "$(<"$nvim_args")" in
    *'--server /tmp/nvim-sidekick'*'sidekick.cli.state'*'external = false'*'terminal = true'*'agents[1].tool.name == _A'*) ;;
    *) false ;;
  esac
  case "$(<"$nvim_args")" in
    *get_lines*|*scrollback*|*transcript*) false ;;
  esac
}

@test "a later unverified hook clears Sidekick host metadata" {
  enable_nvim_stub
  load_plugin
  send_hook_event agents:0.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick

  printf '%s\n' fail >"$nvim_response"
  send_hook_event agents:0.0 codex running sidekick-session-1 turn-2 \
    /tmp/nvim-sidekick

  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_host')" ]
  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_nvim_server')" ]
}

@test "a failed Sidekick request leaves a direct jump switched and warns its client" {
  tmux_test new-session -d -s other -n target -x 80 -y 24
  show_running_codex other:target.0
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:target.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  send_hook_event other:target.0 codex input sidekick-session-1 turn-2 \
    /tmp/nvim-sidekick

  target_id=$(tmux_test display-message -p -t other:target.0 '#{pane_id}')
  target_location=$(tmux_test display-message -p -t "$target_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  printf '%s\n' fail >"$nvim_response"
  attach_status_client
  attach_observer_client
  observer_target=$(client_target "$observer_client_name")
  load_plugin agents:0.0
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$target_location"
  client_target_is "$observer_client_name" "$observer_target"
  retry_until 100 client_messages_contain "$status_client_name" \
    'tmux-agents: Sidekick could not show the Agent'
  case "$(<"$nvim_args")" in
    *"sidekick.cli').show"*'focus = true'*) ;;
    *) false ;;
  esac
  case "$(<"$nvim_args")" in
    *toggle*|*layout*) false ;;
  esac
}

@test "an external Agent keeps its real pane and does not use Sidekick RPC" {
  tmux_test new-session -d -s other -n target -x 80 -y 24
  show_running_codex other:target.0
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:target.0 codex start external-session-1
  send_hook_event other:target.0 codex input external-session-1 turn-2

  target_location=$(tmux_test display-message -p -t other:target.0 \
    '#{session_id}:#{window_id}.#{pane_id}')
  attach_status_client
  load_plugin agents:0.0
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$target_location"
  [ ! -s "$nvim_args" ]
}

@test "chooser navigation opens and focuses a verified Sidekick Agent" {
  tmux_test new-session -d -s other -n target -x 80 -y 24
  show_running_codex other:target.0
  enable_fzf_stub
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:target.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  send_hook_event other:target.0 codex result sidekick-session-1 turn-2 \
    /tmp/nvim-sidekick

  target_id=$(tmux_test display-message -p -t other:target.0 '#{pane_id}')
  target_location=$(tmux_test display-message -p -t "$target_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  tmux_test set-environment -g TMUX_AGENTS_TEST_FZF_SELECTION "$target_id"
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  retry_until 100 client_target_is "$status_client_name" "$target_location"
  retry_until 100 pane_state_is "$target_id" stale
  retry_until 100 sidekick_show_was_requested
  case "$(<"$nvim_args")" in
    *'focus = true'*) ;;
    *) false ;;
  esac
}

@test "the chooser marks a verified Sidekick Agent without changing its Agent type" {
  tmux_test new-session -d -s other -n target -x 80 -y 24
  show_running_codex other:target.0
  enable_fzf_stub
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:target.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  send_hook_event other:target.0 codex result sidekick-session-1 turn-2 \
    /tmp/nvim-sidekick

  target_id=$(tmux_test display-message -p -t other:target.0 '#{pane_id}')
  tmux_test select-pane -t other:target.0 -T 'codex'
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  case "$(<"$chooser_input")" in
    *"$target_id"*'Needs attention · Codex · Sidekick · other:target.0'*) ;;
    *) false ;;
  esac
  case "$(<"$chooser_input")" in
    *"$target_id"$'\t''codex |'*) false ;;
  esac
}

@test "a hidden Sidekick Agent without hook state stays Stale with a chooser warning" {
  tmux_test new-session -d -s other -n sidekick -x 80 -y 24
  tmux_test new-window -d -t other: -n standalone
  show_host_process other:sidekick.0
  show_running_claude other:standalone.0
  enable_fzf_stub
  enable_nvim_stub
  enable_process_snapshot
  sidekick_pane_pid=$(pane_process_id other:sidekick.0)
  standalone_pane_pid=$(pane_process_id other:standalone.0)
  set_process_snapshot \
    "$sidekick_pane_pid 1 bash" \
    "91000001 $sidekick_pane_pid nvim" \
    '91000002 91000001 codex' \
    "$standalone_pane_pid 1 claude"
  set_process_environment \
    '91000002 codex NVIM=/tmp/nvim-sidekick TMUX_AGENTS_PRIVATE_TEST_VALUE=do-not-store'
  load_plugin agents:0.0
  printf '%s\n' hidden >"$nvim_response"
  capture_count="$BATS_TEST_TMPDIR/sidekick-capture-count"
  printf '%s\n' 0 >"$capture_count"
  tmux_test set-environment -g TMUX_AGENTS_TEST_CAPTURE_COUNT "$capture_count"
  tmux_test run-shell "$project_root/scripts/scan.sh"

  [ "$(<"$capture_count")" = '1' ]

  sidekick_id=$(tmux_test display-message -p -t other:sidekick.0 '#{pane_id}')
  standalone_id=$(tmux_test display-message -p -t other:standalone.0 '#{pane_id}')
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  expected_order=$(printf '%s\n' "$sidekick_id" "$standalone_id")
  [ "$(cut -f1 "$chooser_input")" = "$expected_order" ]
  case "$(<"$chooser_input")" in
    *"$sidekick_id"*'Stale · Codex · Sidekick · hook unavailable · other:sidekick.0'*) ;;
    *) false ;;
  esac
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
  case "$(all_runtime_options other:sidekick.0)" in
    *'TMUX_AGENTS_PRIVATE_TEST_VALUE'*|*'do-not-store'*) false ;;
  esac
}

@test "a hidden Sidekick chooser preview shows the editor pane and an open-on-selection notice" {
  tmux_test new-session -d -s other -n sidekick -x 80 -y 24
  show_idle_codex other:sidekick.0
  enable_fzf_stub
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:sidekick.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  printf '%s\n' hidden >"$nvim_response"
  : >"$nvim_args"

  attach_status_client
  load_plugin agents:0.0
  open_chooser

  case "$(<"$chooser_preview")" in
    *'Sidekick Agent is hidden; selecting it will open and focus the Agent.'*'Ask Codex to do anything'*) ;;
    *) false ;;
  esac
  case "$(<"$nvim_args")" in
    *'--server /tmp/nvim-sidekick'*'is_open()'*) ;;
    *) false ;;
  esac
  case "$(<"$nvim_args")" in
    *"sidekick.cli').show"*|*toggle*|*focus*|*get_lines*|*scrollback*|*transcript*) false ;;
  esac
  case "$(all_runtime_options other:sidekick.0)" in
    *'Ask Codex to do anything'*) false ;;
  esac
}

@test "an unavailable Sidekick visibility check does not claim the Agent is hidden" {
  tmux_test new-session -d -s other -n sidekick -x 80 -y 24
  show_idle_codex other:sidekick.0
  enable_fzf_stub
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:sidekick.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  printf '%s\n' unavailable >"$nvim_response"
  : >"$nvim_args"

  attach_status_client
  load_plugin agents:0.0
  open_chooser

  case "$(<"$chooser_preview")" in
    *'Sidekick visibility is unavailable; selecting the Agent will still try to open it.'*) ;;
    *) false ;;
  esac
  case "$(<"$chooser_preview")" in
    *'Sidekick Agent is hidden'*) false ;;
  esac
}

@test "a visible Sidekick terminal uses the ordinary live pane preview" {
  tmux_test new-session -d -s other -n sidekick -x 80 -y 24
  show_running_claude other:sidekick.0
  enable_fzf_stub
  enable_nvim_stub
  load_plugin agents:0.0
  send_hook_event other:sidekick.0 claude start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  : >"$nvim_args"

  attach_status_client
  load_plugin agents:0.0
  open_chooser

  case "$(<"$chooser_preview")" in
    *'Crafting… (4s · esc to interrupt)'*) ;;
    *) false ;;
  esac
  case "$(<"$chooser_preview")" in
    *'Sidekick Agent is hidden'*) false ;;
  esac
  case "$(<"$nvim_args")" in
    *'is_open()'*) ;;
    *) false ;;
  esac
}

@test "lifecycle hooks move an Agent through Running, Input, Reviewable, and removal" {
  load_plugin

  send_hook_event agents:0.0 claude start claude-session-1
  send_hook_event agents:0.0 claude running claude-session-1

  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]

  send_hook_event agents:0.0 claude input claude-session-1 turn-2

  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]

  send_hook_event agents:0.0 claude result claude-session-1 turn-3

  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]

  send_hook_event agents:0.0 claude end claude-session-1

  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "a changed hook session starts fresh state and stale end events are ignored" {
  load_plugin
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1

  send_hook_event agents:0.0 codex start codex-session-2
  send_hook_event agents:0.0 codex running codex-session-1
  send_hook_event agents:0.0 codex end codex-session-1

  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "an unassociated hook end event does not remove a passively tracked Agent" {
  show_idle_codex agents:0.0
  load_plugin

  send_hook_event agents:0.0 codex end codex-session-1

  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]
}

@test "a hook state is not replaced by unmatched screen output" {
  show_idle_codex agents:0.0
  load_plugin
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1

  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]
}

@test "visible Running evidence advances an acknowledged hook Input request" {
  show_codex_approval agents:0.0
  load_plugin
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex input codex-session-1 turn-2

  load_plugin agents:0.0
  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]

  show_running_codex agents:0.0
  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]
}

@test "a hook-reported Reviewable result remains until pane selection acknowledges it" {
  show_idle_claude agents:0.0
  load_plugin
  send_hook_event agents:0.0 claude start claude-session-1
  send_hook_event agents:0.0 claude result claude-session-1 turn-2

  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_attention')" = '1' ]
  tmux_test new-window -d -t agents: -n elsewhere
  tmux_test select-window -t agents:elsewhere
  tmux_test select-window -t agents:0

  retry_until 100 plugin_option_is '@tmux_agents_count_attention' 0
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
}

@test "a hook event refreshes a connected status client without waiting for status interval" {
  show_idle_codex agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'
  tmux_test set-option -g status-interval 999
  load_plugin
  attach_status_client
  attach_observer_client

  status_written=$(client_written "$status_client_name")
  observer_written=$(client_written "$observer_client_name")

  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1

  retry_until 20 status_right_contains '#[fg=colour40]1 #[fg=colour244]0'
  retry_until 20 client_has_written_since "$status_client_name" "$status_written"
  retry_until 20 client_has_written_since "$observer_client_name" "$observer_written"
}

@test "a hook refresh does not trigger another client refresh through status rendering" {
  show_idle_codex agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'
  refresh_count="$BATS_TEST_TMPDIR/refresh-count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_REFRESH_COUNT="$refresh_count"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REFRESH_COUNT "$refresh_count"
  load_plugin
  attach_status_client
  printf '%s\n' 0 >"$refresh_count"

  send_hook_event agents:0.0 codex running codex-session-1
  sleep 0.2

  [ "$(<"$refresh_count")" = '1' ]
}

@test "an ordinary scan does not capture a hook-reported Agent screen" {
  show_idle_codex agents:0.0
  capture_count="$BATS_TEST_TMPDIR/capture-count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_CAPTURE_COUNT="$capture_count"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_CAPTURE_COUNT "$capture_count"
  load_plugin
  printf '%s\n' 0 >"$capture_count"
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1

  load_plugin agents:0.0

  [ "$(<"$capture_count")" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '1' ]
}

@test "a passive scan cannot overwrite a newer hook event" {
  show_idle_codex agents:0.0
  record_passive_codex agents:0.0
  capture_started="$BATS_TEST_TMPDIR/capture-started"
  capture_release="$BATS_TEST_TMPDIR/capture-release"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_CAPTURE_STARTED="$capture_started"
  export TMUX_AGENTS_TEST_CAPTURE_RELEASE="$capture_release"
  export PATH="$test_bin:$PATH"
  server_pid=$(tmux_test display-message -p '#{pid}')
  pane_id=$(tmux_test display-message -p -t agents:0.0 '#{pane_id}')

  TMUX="$socket_path,$server_pid,0" \
    "$project_root/scripts/scan.sh" &
  scan_pid=$!
  retry_until 100 test -f "$capture_started"

  send_hook_event agents:0.0 codex result codex-session-1 turn-2
  : >"$capture_release"
  wait "$scan_pid"

  [ "$(tmux_test show-options -pqv -t "$pane_id" \
    '@tmux_agents_state_source')" = hook ]
  pane_state_is "$pane_id" attention
}

@test "a discovered Agent waits for the default hook grace before passive fallback" {
  show_idle_codex agents:0.0
  tmux_test set-option -gu @tmux_agents_hook_grace_seconds

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_state_source')" = 'grace' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]

  tmux_test set-option -pq -t agents:0.0 '@tmux_agents_fallback_after' 0
  tmux_test run-shell "$project_root/scripts/schedule.sh run-fallback"

  pane_state_is agents:0.0 stale
  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_state_source')" = 'passive' ]
}

@test "a valid hook event removes an Agent from fallback polling immediately" {
  show_idle_codex agents:0.0
  capture_count="$BATS_TEST_TMPDIR/capture-count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_CAPTURE_COUNT="$capture_count"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_CAPTURE_COUNT "$capture_count"
  load_plugin agents:0.0
  printf '%s\n' 0 >"$capture_count"

  send_hook_event agents:0.0 codex start codex-session-1
  tmux_test run-shell "$project_root/scripts/scan.sh"

  [ "$(<"$capture_count")" = '0' ]
  [ "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_state_source')" = 'hook' ]
}

@test "plugin setup schedules the default sixty-second safety reconciliation" {
  load_plugin agents:0.0

  [ "$(tmux_test show-options -gqv '@tmux_agents_safety_scheduled')" = '1' ]
}

@test "fallback polling rearms after a transient scan failure" {
  show_idle_codex agents:0.0
  record_passive_codex agents:0.0
  enable_tmux_command_log
  failure_marker="$BATS_TEST_TMPDIR/capture-failed"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FAIL_COMMAND_ONCE capture-pane
  tmux_test set-environment -g TMUX_AGENTS_TEST_FAILURE_MARKER "$failure_marker"
  tmux_test set-option -g @tmux_agents_fallback_scheduled 1

  tmux_test run-shell "$project_root/scripts/schedule.sh run-fallback"

  [ -f "$failure_marker" ]
  [ "$(tmux_test show-options -gqv '@tmux_agents_fallback_scheduled')" = 1 ]
}

@test "safety reconciliation rearms after a transient process snapshot failure" {
  enable_process_snapshot
  failure_marker="$BATS_TEST_TMPDIR/ps-failed"
  tmux_test set-environment -g TMUX_AGENTS_TEST_FAIL_PS_ONCE "$failure_marker"
  tmux_test set-option -g @tmux_agents_safety_scheduled 1

  tmux_test run-shell "$project_root/scripts/schedule.sh run-safety"

  [ -f "$failure_marker" ]
  [ "$(tmux_test show-options -gqv '@tmux_agents_safety_scheduled')" = 1 ]
}

@test "fallback polling uses bounded tmux queries as unrelated panes grow" {
  show_idle_codex agents:0.0
  record_passive_codex agents:0.0
  pane_number=0
  while [ "$pane_number" -lt 12 ]; do
    tmux_test new-window -d -t agents: -n "unrelated-$pane_number"
    pane_number=$((pane_number + 1))
  done
  enable_tmux_command_log

  tmux_test run-shell "$project_root/scripts/scan.sh"

  show_option_count=$(grep -c '^show-options$' "$tmux_command_log")
  [ "$show_option_count" -le 16 ]
}

@test "an unchanged passive scan does not rewrite pane options" {
  show_idle_codex agents:0.0
  record_passive_codex agents:0.0
  tmux_test set-option -pq -t agents:0.0 '@tmux_agents_evidence' idle
  pane_set_option_count="$BATS_TEST_TMPDIR/pane-set-option-count"
  printf '%s\n' 0 >"$pane_set_option_count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_PANE_SET_OPTION_COUNT="$pane_set_option_count"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$real_tmux"
  tmux_test set-environment -g TMUX_AGENTS_TEST_PANE_SET_OPTION_COUNT \
    "$pane_set_option_count"

  tmux_test run-shell "$project_root/scripts/scan.sh"

  [ "$(<"$pane_set_option_count")" = 0 ]
}

@test "an unchanged hook Agent scan does not redraw status options" {
  show_idle_codex agents:0.0
  set_option_count="$BATS_TEST_TMPDIR/set-option-count"
  export TMUX_AGENTS_TEST_REAL_TMUX="$real_tmux"
  export TMUX_AGENTS_TEST_SET_OPTION_COUNT="$set_option_count"
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$TMUX_AGENTS_TEST_REAL_TMUX"
  tmux_test set-environment -g TMUX_AGENTS_TEST_SET_OPTION_COUNT "$set_option_count"
  load_plugin
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1
  printf '%s\n' 0 >"$set_option_count"

  load_plugin agents:0.0

  [ "$(<"$set_option_count")" = '0' ]
}

@test "a hook outside tmux exits without changing state" {
  load_plugin

  run bash -c "printf '%s\\n' '{\"session_id\":\"codex-session-1\"}' | '$project_root/scripts/hook.sh' codex start"

  [ "$status" -eq 0 ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "debug tracing records scan facts without screen text" {
  show_idle_codex agents:0.0
  tmux_test set-option -g '@tmux_agents_debug' 1
  load_plugin

  send_hook_event agents:0.0 codex start codex-session-1

  debug_messages=$(tmux_test show-messages)
  case "$debug_messages" in
    *'tmux-agents debug: transition'*'new=stale'*) ;;
    *) false ;;
  esac
  case "$debug_messages" in
    *'tmux-agents debug: hook event='*|*'tmux-agents debug: scan pane='*) false ;;
  esac
  case "$debug_messages" in
    *'Ask Codex to do anything'*|*'100% left'*) false ;;
  esac
}

@test "diagnostics report a healthy hook and its last activity" {
  show_host_process agents:0.0
  enable_process_snapshot
  pane_pid=$(pane_process_id agents:0.0)
  set_process_snapshot \
    "$pane_pid 1 bash" \
    "91000001 $pane_pid codex"
  load_plugin
  send_hook_event agents:0.0 codex start codex-session-1
  send_hook_event agents:0.0 codex running codex-session-1 turn-2

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'pane='*' type=codex process=91000001'*'hook=healthy'*\
'last-hook-activity='*'identity=codex-session-1'*\
'state=running source=hook fallback=inactive'*'sidekick=standalone'*) ;;
    *) false ;;
  esac
  case "$output" in
    *'Ask Codex to do anything'*|*'100% left'*) false ;;
  esac
}

@test "diagnostics distinguish a missing startup hook from active passive fallback" {
  show_host_process agents:0.0
  tmux_test new-window -d -t agents: -n waiting
  show_host_process agents:waiting.0
  enable_process_snapshot
  fallback_pane_pid=$(pane_process_id agents:0.0)
  waiting_pane_pid=$(pane_process_id agents:waiting.0)
  set_process_snapshot \
    "$fallback_pane_pid 1 bash" \
    "91000001 $fallback_pane_pid codex"
  load_plugin
  tmux_test set-option -g @tmux_agents_hook_grace_seconds 30
  set_process_snapshot \
    "$fallback_pane_pid 1 bash" \
    "91000001 $fallback_pane_pid codex" \
    "$waiting_pane_pid 1 bash" \
    "92000001 $waiting_pane_pid claude"
  capture_count="$BATS_TEST_TMPDIR/diagnostic-capture-count"
  printf '%s\n' 0 >"$capture_count"
  tmux_test set-environment -g TMUX_AGENTS_TEST_CAPTURE_COUNT "$capture_count"

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'type=codex process=91000001 hook=missing last-hook-activity=never'*\
'source=passive fallback=active'*) ;;
    *) false ;;
  esac
  case "$output" in
    *'type=claude process=92000001 hook=missing-startup-hook last-hook-activity=never'*\
'state=unclassified source=grace fallback=pending'*) ;;
    *) false ;;
  esac
  [ "$(<"$capture_count")" = '0' ]
}

@test "diagnostics distinguish unsupported Sidekick hosting from a stale RPC address" {
  show_host_process agents:0.0
  enable_nvim_stub
  enable_process_snapshot
  pane_pid=$(pane_process_id agents:0.0)
  set_process_snapshot \
    "$pane_pid 1 bash" \
    "91000001 $pane_pid nvim" \
    '91000002 91000001 codex'
  set_process_environment \
    '91000002 codex NVIM=/tmp/nvim-sidekick'
  printf '%s\n' unsupported >"$nvim_response"

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'type=codex process=91000002'*'sidekick=unsupported-host rpc=reachable'*) ;;
    *) false ;;
  esac

  printf '%s\n' 1 >"$nvim_response"

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'sidekick=verified rpc=reachable'*) ;;
    *) false ;;
  esac

  send_hook_event agents:0.0 codex start sidekick-session-1 turn-1 \
    /tmp/nvim-sidekick
  printf '%s\n' fail >"$nvim_response"

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'hook=healthy'*\
'sidekick=previously-verified rpc=unreachable address=possibly-stale'*) ;;
    *) false ;;
  esac
  case "$(<"$nvim_args")" in
    *get_lines*|*scrollback*|*transcript*) false ;;
  esac
}

@test "diagnostics report an actionable Agent running outside the current tmux server" {
  show_host_process agents:0.0
  enable_process_snapshot
  pane_pid=$(pane_process_id agents:0.0)
  set_process_snapshot \
    "$pane_pid 1 bash" \
    '91000001 1 claude'

  run run_diagnostics

  [ "$status" -eq 0 ]
  case "$output" in
    *'pane=none location=outside-current-tmux-server type=claude process=91000001'*\
'state=untracked'*'reason=no-containing-pane'*\
'action=run-in-containing-tmux-server-or-start-agent-in-tmux'*) ;;
    *) false ;;
  esac
}

@test "the diagnostic command explains that it must run inside tmux" {
  run env TMUX= "$project_root/scripts/diagnose.sh"

  [ "$status" -eq 1 ]
  [ "$output" = 'tmux-agents: diagnostics must run inside tmux' ]
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
  [ "$(plugin_option '@tmux_agents_count_stale')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
  retry_until 100 status_right_contains '󰚩 2'
  [ "$(tmux_test show-options -pqv -t agents:background.0 '@tmux_agents_state')" = 'stale' ]

  runtime_options=$(all_runtime_options agents:0.0)
  case "$runtime_options" in
    *'Ask Codex to do anything'*|*'100% left'*) false ;;
  esac
  [ -z "$(tmux_test show-options -gqv '@tmux_agents_state')" ]
  [ -z "$(tmux_test show-options -wqv -t agents:0.0 '@tmux_agents_state')" ]

  tmux_test split-window -d -t agents:0.0
  tmux_test select-pane -t agents:0.1
  load_plugin agents:0.1

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
}

@test "a scan ignores scrollback and does not persist captured text" {
  scrollback_marker="tmux-agents-private-$BATS_TEST_NUMBER-$$"
  tmux_test respawn-pane -k -t agents:0.0 \
    "$project_root/tests/fixtures/show-codex-unsupported-with-scrollback.sh '$test_bin/codex' '$scrollback_marker'"
  retry_until 50 pane_current_command_is agents:0.0 codex

  full_history=$(tmux_test capture-pane -p -S - -t agents:0.0)
  case "$full_history" in
    *"$scrollback_marker"*'• Working (1s • esc to interrupt)'*) ;;
    *) false ;;
  esac

  load_plugin agents:0.0

  pane_state_is agents:0.0 stale
  runtime_options=$(all_runtime_options agents:0.0)
  case "$runtime_options" in
    *"$scrollback_marker"*|*'Visible output has no supported evidence.'*) false ;;
  esac
  [ -z "$(find "$BATS_TEST_TMPDIR" -type f ! -path "$test_bin/*" -print -quit)" ]
}

@test "a first-discovered background idle Codex Agent is Stale" {
  tmux_test new-window -d -t agents: -n background
  show_idle_codex agents:background.0

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:background.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
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

@test "passive Agent state records source and evidence without screen text" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0
  pane_id=$(tmux_test display-message -p -t agents:input.0 '#{pane_id}')

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_state_source')" = 'passive' ]
  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_evidence')" = 'input' ]
  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_state_since')" -gt 0 ]
  [ "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_attention_evidence')" = 'input' ]
  [ -n "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_attention_signature')" ]
  [ -z "$(tmux_test show-options -pqv -t "$pane_id" '@tmux_agents_acknowledged_signature')" ]

  tmux_test select-window -t agents:input

  retry_until 100 pane_attention_is_acknowledged "$pane_id"
  runtime_options=$(all_runtime_options agents:input.0)
  case "$runtime_options" in
    *'Would you like to run the following command?'*|*'git status --short'*) false ;;
  esac
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

@test "a replaced passive Codex Agent begins stale rather than inheriting old work" {
  tmux_test new-window -d -t agents: -n reviewable
  show_running_codex agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'running' ]

  show_codex_result agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]

  attention_since=$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state_since')
  case "$attention_since" in
    ''|*[!0-9]*) false ;;
  esac

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state_since')" = "$attention_since" ]
}

@test "a replaced passive Claude Code Agent begins stale rather than inheriting old work" {
  tmux_test new-window -d -t agents: -n reviewable
  show_running_claude agents:reviewable.0
  load_plugin agents:0.0

  show_claude_result agents:reviewable.0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:reviewable.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_attention')" = '0' ]
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

@test "ordinary pane selection acknowledges a hook Reviewable result as Stale" {
  tmux_test new-window -d -t agents: -n reviewable
  show_idle_claude agents:reviewable.0
  load_plugin agents:0.0
  send_hook_event agents:reviewable.0 claude start claude-session-1
  send_hook_event agents:reviewable.0 claude result claude-session-1 turn-2

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

  tmux_test select-window -t agents:0
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'attention' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state_since')" -ge "$attention_since" ]
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

  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(tmux_test show-options -pv -t agents:input.0 '@tmux_agents_identity')" != '' ]
}

@test "an unsupported Agent screen is Stale" {
  show_unsupported_agent agents:0.0 codex

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_type')" = 'codex' ]
  [ "$(tmux_test show-options -pv -t agents:0.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(plugin_option '@tmux_agents_count_running')" = '0' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
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
  [ "$(tmux_test show-options -pv -t agents:codex-agent.0 '@tmux_agents_state')" = 'stale' ]
  [ "$(tmux_test show-options -pv -t other:0.0 '@tmux_agents_state')" = 'stale' ]
  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_type')" ]
  [ -z "$(tmux_test show-options -pqv -t agents:0.0 '@tmux_agents_state')" ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
}

@test "process-tree discovery finds wrapped and hosted Agents from one shared snapshot" {
  tmux_test new-window -d -t agents: -n wrapper
  tmux_test new-window -d -t agents: -n host
  show_host_process agents:wrapper.0
  show_host_process agents:host.0
  enable_process_snapshot

  wrapper_pid=$(pane_process_id agents:wrapper.0)
  host_pid=$(pane_process_id agents:host.0)
  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4101 $wrapper_pid wrapper" \
    '4102 4101 claude' \
    "$host_pid 1 bash" \
    "4201 $host_pid nvim" \
    '4202 4201 codex'

  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_type')" = 'claude' ]
  [ "$(tmux_test show-options -pv -t agents:host.0 '@tmux_agents_type')" = 'codex' ]
  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_identity')" = 'pid:4102' ]
  [ "$(tmux_test show-options -pv -t agents:host.0 '@tmux_agents_identity')" = 'pid:4202' ]
  [ "$(plugin_option '@tmux_agents_count_stale')" = '2' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '2' ]
  [ "$(<"$process_snapshot_count")" = '1' ]
}

@test "process-tree discovery parses its shared snapshot once for all panes" {
  pane_number=0
  while [ "$pane_number" -lt 8 ]; do
    tmux_test new-window -d -t agents: -n "shell-$pane_number"
    pane_number=$((pane_number + 1))
  done
  enable_process_snapshot
  : >"$process_snapshot"
  while IFS= read -r pane_pid; do
    printf '%s 1 bash\n' "$pane_pid" >>"$process_snapshot"
  done < <(tmux_test list-panes -a -F '#{pane_pid}')
  awk_log="$BATS_TEST_TMPDIR/awk-log"
  : >"$awk_log"
  export TMUX_AGENTS_TEST_AWK_LOG="$awk_log"
  tmux_test set-environment -g TMUX_AGENTS_TEST_AWK_LOG "$awk_log"

  tmux_test run-shell "$project_root/scripts/reconcile.sh"

  [ "$(wc -l <"$awk_log" | tr -d ' ')" = 1 ]
}

@test "hookless Sidekick discovery batches Agent environment lookup across panes" {
  tmux_test new-window -d -t agents: -n codex-host
  tmux_test new-window -d -t agents: -n claude-host
  show_host_process agents:codex-host.0
  show_host_process agents:claude-host.0
  enable_nvim_stub
  enable_process_snapshot

  codex_host_pid=$(pane_process_id agents:codex-host.0)
  claude_host_pid=$(pane_process_id agents:claude-host.0)
  set_process_snapshot \
    "$codex_host_pid 1 bash" \
    "93000001 $codex_host_pid nvim" \
    '93000002 93000001 codex' \
    "$claude_host_pid 1 bash" \
    "94000001 $claude_host_pid nvim" \
    '94000002 94000001 claude'
  set_process_environment \
    '93000002 codex NVIM=/tmp/nvim-codex' \
    '94000002 claude NVIM=/tmp/nvim-claude'

  load_plugin agents:0.0

  [ "$(<"$process_snapshot_count")" = '1' ]
  [ "$(<"$process_environment_count")" = '1' ]
  [ "$(tmux_test show-options -pqv -t agents:codex-host.0 \
    '@tmux_agents_nvim_server')" = '/tmp/nvim-codex' ]
  [ "$(tmux_test show-options -pqv -t agents:claude-host.0 \
    '@tmux_agents_nvim_server')" = '/tmp/nvim-claude' ]
}

@test "process-tree reconciliation resets replaced Agents and removes exited ones" {
  tmux_test new-window -d -t agents: -n wrapper
  show_host_process agents:wrapper.0
  enable_process_snapshot

  wrapper_pid=$(pane_process_id agents:wrapper.0)
  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4301 $wrapper_pid codex"
  load_plugin agents:0.0
  tmux_test set-option -pq -t agents:wrapper.0 '@tmux_agents_state_since' 1

  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4302 $wrapper_pid codex"
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_identity')" = 'pid:4302' ]
  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_state_since')" -gt 1 ]

  set_process_snapshot "$wrapper_pid 1 bash"
  load_plugin agents:0.0

  [ -z "$(tmux_test show-options -pqv -t agents:wrapper.0 '@tmux_agents_type')" ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '0' ]
}

@test "process-tree reconciliation replaces an old hook Agent with a passive Agent" {
  tmux_test new-window -d -t agents: -n wrapper
  show_host_process agents:wrapper.0
  enable_process_snapshot

  wrapper_pid=$(pane_process_id agents:wrapper.0)
  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4401 $wrapper_pid codex"
  load_plugin agents:0.0
  tmux_test set-option -puq -t agents:wrapper.0 '@tmux_agents_process_identity'
  send_hook_event agents:wrapper.0 codex start codex-session-1
  send_hook_event agents:wrapper.0 codex running codex-session-1
  tmux_test set-option -pq -t agents:wrapper.0 '@tmux_agents_state_since' 1

  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4402 $wrapper_pid claude"
  load_plugin agents:0.0

  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_type')" = 'claude' ]
  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_state_source')" = 'passive' ]
  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_identity')" = 'pid:4402' ]
  [ "$(tmux_test show-options -pv -t agents:wrapper.0 '@tmux_agents_state_since')" -gt 1 ]
}

@test "a hook start does not take a process snapshot" {
  tmux_test new-window -d -t agents: -n wrapper
  show_host_process agents:wrapper.0
  enable_process_snapshot

  wrapper_pid=$(pane_process_id agents:wrapper.0)
  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4501 $wrapper_pid codex"
  load_plugin agents:0.0
  printf '%s\n' 0 >"$process_snapshot_count"
  send_hook_event agents:wrapper.0 codex start codex-session-1

  [ "$(<"$process_snapshot_count")" = '0' ]
}

@test "a non-start hook event does not take a process snapshot" {
  tmux_test new-window -d -t agents: -n wrapper
  show_host_process agents:wrapper.0
  enable_process_snapshot

  wrapper_pid=$(pane_process_id agents:wrapper.0)
  set_process_snapshot \
    "$wrapper_pid 1 bash" \
    "4601 $wrapper_pid codex"
  load_plugin agents:0.0
  printf '%s\n' 0 >"$process_snapshot_count"

  send_hook_event agents:wrapper.0 codex running codex-session-1

  [ "$(<"$process_snapshot_count")" = '0' ]
}

@test "closing an Agent pane removes it from the counts" {
  tmux_test new-window -d -t agents: -n background
  show_idle_claude agents:background.0
  load_plugin agents:0.0

  [ "$(plugin_option '@tmux_agents_count_stale')" = '1' ]
  [ "$(plugin_option '@tmux_agents_count_total')" = '1' ]

  tmux_test kill-pane -t agents:background.0

  retry_until 100 plugin_option_is '@tmux_agents_count_stale' 0
  retry_until 100 plugin_option_is '@tmux_agents_count_total' 0
}

@test "the default widget shows nonzero Running in green before Stale" {
  tmux_test new-window -d -t agents: -n running
  tmux_test new-window -d -t agents: -n unsupported
  show_running_codex agents:running.0
  show_unsupported_agent agents:unsupported.0 claude
  show_idle_codex agents:0.0
  tmux_test set-option -g status-right '#{tmux_agents}'

  load_plugin agents:0.0

  retry_until 100 status_right_contains '#[fg=colour40]1 #[fg=colour244]2'
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

@test "ordinary status rendering performs no discovery or screen capture" {
  tmux_test set-option -g status-right '#{tmux_agents}'
  capture_count="$BATS_TEST_TMPDIR/capture-count"
  enable_process_snapshot
  set_process_snapshot "$(pane_process_id agents:0.0) 1 bash"
  export TMUX_AGENTS_TEST_CAPTURE_COUNT="$capture_count"
  tmux_test set-environment -g TMUX_AGENTS_TEST_CAPTURE_COUNT "$capture_count"
  load_plugin agents:0.0
  attach_status_client
  printf '%s\n' 0 >"$capture_count"
  printf '%s\n' 0 >"$process_snapshot_count"

  tmux_test refresh-client -t "$status_client_name" -S
  tmux_test display-message -p '#{E:status-right}' >/dev/null

  [ "$(<"$capture_count")" = '0' ]
  [ "$(<"$process_snapshot_count")" = '0' ]
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

@test "the obsolete scan placeholder is not installed or executed" {
  tmux_test new-window -d -t agents: -n running
  show_running_codex agents:running.0
  tmux_test set-option -g status-right \
    'Agents: #{@tmux_agents_count_running}#{tmux_agents_scan}'
  attach_status_client

  load_plugin agents:0.0

  installed_status=$(tmux_test show-options -gv status-right)
  [ "$installed_status" = 'Agents: #{@tmux_agents_count_running}#{tmux_agents_scan}' ]
  retry_until 100 status_right_contains 'Agents: 1'
  [ "$(tmux_test display-message -p '#{E:status-right}')" = 'Agents: 1' ]
}

@test "the chooser groups Agents with useful context and a live screen preview" {
  tmux_test new-window -d -t agents: -n older-attention
  tmux_test new-window -d -t agents: -n newer-attention
  tmux_test new-window -d -t agents: -n stale
  tmux_test new-window -d -t agents: -n another-stale
  tmux_test new-window -d -t agents: -n running
  show_codex_approval agents:older-attention.0
  show_claude_approval agents:newer-attention.0
  show_idle_claude agents:stale.0
  show_idle_codex agents:another-stale.0
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
  tmux_test select-pane -t agents:another-stale.0 -T ''
  tmux_test select-pane -t agents:running.0 -T 'Index the docs'

  older_id=$(tmux_test display-message -p -t agents:older-attention.0 '#{pane_id}')
  newer_id=$(tmux_test display-message -p -t agents:newer-attention.0 '#{pane_id}')
  stale_id=$(tmux_test display-message -p -t agents:stale.0 '#{pane_id}')
  another_stale_id=$(tmux_test display-message -p -t agents:another-stale.0 '#{pane_id}')
  running_id=$(tmux_test display-message -p -t agents:running.0 '#{pane_id}')

  enable_fzf_stub
  attach_status_client
  load_plugin agents:0.0
  open_chooser

  expected_order=$(printf '%s\n' \
    "$older_id" "$newer_id" "$stale_id" "$another_stale_id" "$running_id")
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
    *"$another_stale_id	Stale · Codex · agents:another-stale.0 · "*) ;;
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
    *'--preview='*) ;;
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

@test "the chooser lists Agents promptly as unrelated panes grow" {
  tmux_test new-window -d -t agents: -n input
  show_codex_approval agents:input.0
  pane_number=0
  while [ "$pane_number" -lt 10 ]; do
    tmux_test new-window -d -t agents: -n "unrelated-$pane_number"
    pane_number=$((pane_number + 1))
  done
  load_plugin agents:0.0

  enable_fzf_stub
  tmux_test set-environment -g TMUX_AGENTS_TEST_COMMAND_DELAY 0.02
  attach_status_client
  open_chooser

  case "$(<"$chooser_input")" in
    *'Needs attention · Codex · agents:input.0'*) ;;
    *) false ;;
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
  send_hook_event other:target.1 codex start codex-session-1
  send_hook_event other:target.1 codex result codex-session-1 turn-2

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
  [ "$(tmux_test show-options -pv -t "$target_id" '@tmux_agents_state')" = 'stale' ]

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

@test "direct jump refreshes the queue and switches only its client to the oldest Input request" {
  tmux_test new-session -d -s other -n no-longer-waiting -x 80 -y 24
  tmux_test new-window -d -t other: -n oldest-waiting
  tmux_test new-window -d -t other: -n newer-waiting
  show_codex_approval other:no-longer-waiting.0
  show_claude_approval other:oldest-waiting.0
  show_codex_question other:newer-waiting.0
  load_plugin agents:0.0

  tmux_test set-option -pq -t other:no-longer-waiting.0 \
    '@tmux_agents_state_since' 10
  tmux_test set-option -pq -t other:oldest-waiting.0 \
    '@tmux_agents_state_since' 20
  tmux_test set-option -pq -t other:newer-waiting.0 \
    '@tmux_agents_state_since' 30
  show_running_codex other:no-longer-waiting.0

  oldest_id=$(tmux_test display-message -p -t other:oldest-waiting.0 '#{pane_id}')
  oldest_location=$(tmux_test display-message -p -t "$oldest_id" \
    '#{session_id}:#{window_id}.#{pane_id}')

  attach_status_client
  attach_observer_client
  observer_target=$(client_target "$observer_client_name")
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$oldest_location"
  client_target_is "$observer_client_name" "$observer_target"
  pane_state_is other:no-longer-waiting.0 running
  case "$(tmux_test list-keys -T prefix a)" in
    *fzf*) false ;;
  esac
}

@test "direct jump responds promptly as unrelated panes grow" {
  tmux_test new-session -d -s other -n input -x 80 -y 24
  show_codex_approval other:input.0
  pane_number=0
  while [ "$pane_number" -lt 10 ]; do
    tmux_test new-window -d -t agents: -n "unrelated-$pane_number"
    pane_number=$((pane_number + 1))
  done
  load_plugin agents:0.0

  input_id=$(tmux_test display-message -p -t other:input.0 '#{pane_id}')
  input_location=$(tmux_test display-message -p -t "$input_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  tmux_test set-environment -g PATH "$test_bin:$PATH"
  tmux_test set-environment -g TMUX_AGENTS_TEST_REAL_TMUX "$real_tmux"
  tmux_test set-environment -g TMUX_AGENTS_TEST_COMMAND_DELAY 0.02
  attach_status_client

  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$input_location"
}

@test "repeated direct jumps drain Reviewable results from oldest to newest" {
  tmux_test new-session -d -s other -n oldest-result -x 80 -y 24
  tmux_test new-window -d -t other: -n newer-result
  show_running_codex other:oldest-result.0
  show_running_claude other:newer-result.0
  load_plugin agents:0.0
  send_hook_event other:oldest-result.0 codex start codex-session-1
  send_hook_event other:newer-result.0 claude start claude-session-2
  send_hook_event other:oldest-result.0 codex result codex-session-1 turn-2
  send_hook_event other:newer-result.0 claude result claude-session-2 turn-2

  tmux_test set-option -pq -t other:oldest-result.0 \
    '@tmux_agents_state_since' 10
  tmux_test set-option -pq -t other:newer-result.0 \
    '@tmux_agents_state_since' 20
  oldest_id=$(tmux_test display-message -p -t other:oldest-result.0 '#{pane_id}')
  newer_id=$(tmux_test display-message -p -t other:newer-result.0 '#{pane_id}')
  oldest_location=$(tmux_test display-message -p -t "$oldest_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  newer_location=$(tmux_test display-message -p -t "$newer_id" \
    '#{session_id}:#{window_id}.#{pane_id}')

  attach_status_client
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$oldest_location"
  retry_until 100 pane_state_is "$oldest_id" stale
  pane_state_is "$newer_id" attention

  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$newer_location"
  retry_until 100 pane_state_is "$newer_id" stale
  retry_until 100 plugin_option_is '@tmux_agents_count_attention' 0
}

@test "an unresolved Input request returns to the direct-jump queue after leaving" {
  tmux_test new-session -d -s other -n input -x 80 -y 24
  show_codex_approval other:input.0
  load_plugin agents:0.0
  tmux_test set-option -pq -t other:input.0 '@tmux_agents_state_since' 1

  input_id=$(tmux_test display-message -p -t other:input.0 '#{pane_id}')
  input_location=$(tmux_test display-message -p -t "$input_id" \
    '#{session_id}:#{window_id}.#{pane_id}')
  original_location=$(tmux_test display-message -p -t agents:0.0 \
    '#{session_id}:#{window_id}.#{pane_id}')

  attach_status_client
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$input_location"
  pane_state_is "$input_id" attention

  tmux_test switch-client -c "$status_client_name" -t agents:0.0
  retry_until 100 client_target_is "$status_client_name" "$original_location"
  printf '\002a' >&9

  retry_until 100 client_target_is "$status_client_name" "$input_location"
  pane_state_is "$input_id" attention
}

@test "a configurable direct jump reports an empty queue without moving" {
  tmux_test set-option -g '@tmux_agents_jump_key' j
  attach_status_client
  original_target=$(client_target "$status_client_name")
  load_plugin agents:0.0

  printf '\002j' >&9

  retry_until 100 client_messages_contain "$status_client_name" \
    'tmux-agents: no Agent needs attention'
  client_target_is "$status_client_name" "$original_target"
}

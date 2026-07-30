#!/usr/bin/env bats

setup() {
  project_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  socket_path="$BATS_TEST_TMPDIR/tmux.sock"
  test_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$test_bin"
  cp "$(command -v bash)" "$test_bin/codex"
  cp "$(command -v bash)" "$test_bin/claude"

  tmux_test new-session -d -s agents -x 80 -y 24
  tmux_test set-option -g remain-on-exit on
}

teardown() {
  tmux_test kill-server >/dev/null 2>&1 || true
  if [ -n "${status_client_pid:-}" ]; then
    exec 9>&-
    wait "$status_client_pid" >/dev/null 2>&1 || true
  fi
}

tmux_test() {
  TMUX= tmux -S "$socket_path" -f /dev/null "$@"
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

attach_status_client() {
  status_client_pipe="$BATS_TEST_TMPDIR/status-client.pipe"
  mkfifo "$status_client_pipe"
  exec 9<>"$status_client_pipe"

  case "$(uname -s)" in
    Darwin)
      script -q /dev/null env TMUX= TERM=xterm-256color \
        tmux -S "$socket_path" -f /dev/null attach-session -t agents \
        <&9 >/dev/null 2>&1 &
      ;;
    *)
      script -q -c \
        "env TMUX= TERM=xterm-256color tmux -S '$socket_path' -f /dev/null attach-session -t agents" \
        /dev/null <&9 >/dev/null 2>&1 &
      ;;
  esac
  status_client_pid=$!

  retry_until 50 status_client_is_attached
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

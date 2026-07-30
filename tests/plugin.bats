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
}

tmux_test() {
  TMUX= tmux -S "$socket_path" -f /dev/null "$@"
}

plugin_option() {
  tmux_test show-options -gv "$1"
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

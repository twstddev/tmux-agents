#!/usr/bin/env bash

# Neovim RPC boundary for the non-content Sidekick integration.

sidekick_rpc_target_is_valid() {
  sidekick_rpc_type=$1
  sidekick_rpc_server=$2

  case "$sidekick_rpc_type" in
  codex | claude) ;;
  *) return 1 ;;
  esac
  [ -n "$sidekick_rpc_server" ] || return 1
  command -v nvim >/dev/null 2>&1 || return 1
}

sidekick_remote_expr() {
  sidekick_rpc_server=$1
  sidekick_rpc_expression=$2

  nvim --server "$sidekick_rpc_server" --remote-expr \
    "$sidekick_rpc_expression" 2>/dev/null
}

sidekick_rpc_status() {
  sidekick_server=$1

  if [ -z "$sidekick_server" ]; then
    printf '%s\n' 'address-unavailable'
  elif ! command -v nvim >/dev/null 2>&1; then
    printf '%s\n' 'client-unavailable'
  elif sidekick_rpc_result=$(sidekick_remote_expr "$sidekick_server" '1'); then
    if [ "$sidekick_rpc_result" = '1' ]; then
      printf '%s\n' 'reachable'
    else
      printf '%s\n' 'unexpected-response'
    fi
  else
    printf '%s\n' 'unreachable'
  fi
}

sidekick_embedded_state_expression() {
  sidekick_query_type=$1
  sidekick_query_condition=${2-true}
  sidekick_query_unavailable=${3-0}

  printf '%s' "luaeval(\"(function() local ok, State = pcall(require, 'sidekick.cli.state'); if not ok then return $sidekick_query_unavailable end; local agents = State.get({ external = false, terminal = true }); if not (#agents == 1 and agents[1].session ~= nil and agents[1].tool.name == _A) then return $sidekick_query_unavailable end; return $sidekick_query_condition and 1 or 0 end)()\", \"$sidekick_query_type\")"
}

sidekick_verifies_embedded_host() {
  sidekick_type=$1
  sidekick_server=$2

  sidekick_rpc_target_is_valid "$sidekick_type" "$sidekick_server" || return 1

  sidekick_verify_expression=$(sidekick_embedded_state_expression \
    "$sidekick_type")
  sidekick_result=$(sidekick_remote_expr "$sidekick_server" \
    "$sidekick_verify_expression") || return 1

  [ "$sidekick_result" = '1' ]
}

sidekick_show_and_focus() {
  sidekick_type=$1
  sidekick_server=$2

  sidekick_rpc_target_is_valid "$sidekick_type" "$sidekick_server" || return 1

  sidekick_show_expression="luaeval(\"require('sidekick.cli').show({ name = _A, focus = true })\", \"$sidekick_type\")"
  sidekick_remote_expr "$sidekick_server" "$sidekick_show_expression" \
    >/dev/null
}

sidekick_terminal_visibility() {
  sidekick_type=$1
  sidekick_server=$2

  sidekick_rpc_target_is_valid "$sidekick_type" "$sidekick_server" || return 1

  sidekick_visible_expression=$(sidekick_embedded_state_expression \
    "$sidekick_type" 'agents[1].terminal:is_open()' 2)
  sidekick_visible=$(sidekick_remote_expr "$sidekick_server" \
    "$sidekick_visible_expression") || return 1

  case "$sidekick_visible" in
  1) printf '%s\n' visible ;;
  0) printf '%s\n' hidden ;;
  *) return 1 ;;
  esac
}

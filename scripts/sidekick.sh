#!/usr/bin/env bash

# Neovim RPC boundary for the non-content Sidekick integration.

sidekick_verifies_embedded_host() {
  sidekick_type=$1
  sidekick_server=$2

  case "$sidekick_type" in
  codex | claude) ;;
  *) return 1 ;;
  esac
  [ -n "$sidekick_server" ] || return 1
  command -v nvim >/dev/null 2>&1 || return 1

  sidekick_verify_expression="luaeval(\"(function() local ok, State = pcall(require, 'sidekick.cli.state'); if not ok then return 0 end; local agents = State.get({ external = false, terminal = true }); return #agents == 1 and agents[1].session ~= nil and agents[1].tool.name == _A and 1 or 0 end)()\", \"$sidekick_type\")"
  sidekick_result=$(nvim --server "$sidekick_server" --remote-expr \
    "$sidekick_verify_expression" 2>/dev/null) || return 1

  [ "$sidekick_result" = '1' ]
}

sidekick_show_and_focus() {
  sidekick_type=$1
  sidekick_server=$2

  case "$sidekick_type" in
  codex | claude) ;;
  *) return 1 ;;
  esac
  [ -n "$sidekick_server" ] || return 1
  command -v nvim >/dev/null 2>&1 || return 1

  sidekick_show_expression="luaeval(\"require('sidekick.cli').show({ name = _A, focus = true })\", \"$sidekick_type\")"
  nvim --server "$sidekick_server" --remote-expr "$sidekick_show_expression" \
    >/dev/null 2>&1
}

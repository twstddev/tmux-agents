#!/usr/bin/env bash

# One tmux client returns all plugin-owned pane metadata. The Neovim address is
# last so shell read keeps any delimiter characters in that external value.
pane_tracking_snapshot() {
  tmux list-panes -a -F '#{pane_id}|#{@tmux_agents_state}|#{@tmux_agents_type}|#{@tmux_agents_state_source}|#{@tmux_agents_identity}|#{@tmux_agents_process_identity}|#{@tmux_agents_evidence}|#{@tmux_agents_state_since}|#{@tmux_agents_attention_evidence}|#{@tmux_agents_attention_signature}|#{@tmux_agents_acknowledged_signature}|#{@tmux_agents_fallback_after}|#{@tmux_agents_host}|#{@tmux_agents_nvim_server}'
}

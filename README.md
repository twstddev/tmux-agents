# tmux-agents

`tmux-agents` shows a robot bubble when a supported Codex or Claude Code
interaction needs your attention. It counts marked panes in the current tmux
server and lets you jump to the oldest one.

## Requirements

- Linux or macOS
- tmux and [TPM](https://github.com/tmux-plugins/tpm)
- A Nerd Font that includes the robot and rounded-cap glyphs
- Codex and/or Claude Code for the optional companion plugins

## Install

Add the plugin to `~/.tmux.conf`:

```tmux
set -g @plugin 'twstd/tmux-agents'
set -g status-right '#{tmux_agents}'
run '~/.tmux/plugins/tpm/tpm'
```

Reload tmux and press `prefix` + `I` to install the plugin through TPM. The
placeholder can be placed in `status-left` instead if preferred. The bubble
uses a white foreground and red background by default; customize them with
`@tmux_agents_attention_fg` and `@tmux_agents_attention_bg`.

Press `prefix` + `a` to jump to the oldest marked pane across the current tmux
server. Navigation does not clear the marker; the Agent's lifecycle hook does.

## Agent companions

Install the companion for each Agent you use after installing the tmux plugin.

### Codex

```sh
codex plugin marketplace add ~/.tmux/plugins/tmux-agents/plugins/codex
codex plugin add tmux-agents@tmux-agents
```

Review and trust the hooks through Codex's native `/hooks` workflow. Permission
requests are supported. Native structured `request_user_input` questions are
not tracked, and a permission marker may remain until later tool or turn
activity clears it.

### Claude Code

```sh
claude plugin marketplace add ~/.tmux/plugins/tmux-agents/plugins/claude
claude plugin install tmux-agents@tmux-agents
```

Review and trust the hooks through Claude Code's native plugin workflow.
Permission prompts, `AskUserQuestion`, plan approval, and MCP elicitation are
supported. Matching responses and later lifecycle activity clear the marker.

# tmux-agents

`tmux-agents` shows a red robot bubble when a supported Agent interaction needs
your attention. It counts marked panes across the current tmux server and
refreshes immediately when a marker is marked or cleared.

## Current setup

Install through TPM:

```tmux
set -g @plugin 'twstd/tmux-agents'
set -g status-right '#{tmux_agents}'
```

The bubble uses a white foreground and red background by default. Customize
them with `@tmux_agents_attention_fg` and `@tmux_agents_attention_bg`.

The shared mark and clear hook is available to companion Agent plugins. Codex
and Claude Code companion integrations are planned for a later v1 slice.

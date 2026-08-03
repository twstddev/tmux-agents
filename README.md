# tmux-agents

`tmux-agents` shows a red robot bubble when a supported Agent interaction needs
your attention. It counts marked panes across the current tmux server and
refreshes immediately when a marker is marked or cleared.

## Setup

Install through TPM:

```tmux
set -g @plugin 'twstd/tmux-agents'
set -g status-right '#{tmux_agents}'
```

The bubble uses a white foreground and red background by default. Customize
them with `@tmux_agents_attention_fg` and `@tmux_agents_attention_bg`.

Press prefix plus lowercase `a` to jump to the oldest marked pane across the
current tmux server. The marker remains until the Agent's lifecycle hook clears
it. If the queue is empty, tmux displays `No agents need attention`.

The shared mark and clear hook is available to companion Agent plugins. Codex
permission prompts are supported through the included local Codex plugin:

```sh
codex plugin marketplace add ~/.tmux/plugins/tmux-agents/plugins/codex
codex plugin add tmux-agents@tmux-agents
```

Review and trust the plugin hooks with Codex's `/hooks` command. Codex's native
structured `request_user_input` questions are not tracked, and a permission
marker may remain until later tool or turn activity clears it.

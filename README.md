# tmux-agents

A lightweight tmux plugin for tracking Codex and Claude Code agents across sessions.

It discovers Codex and Claude Code panes across the current tmux server and classifies them as Needs attention, Running, Unknown, or Stale.

## Current capabilities

- Discovers foreground `codex` and `claude` processes across all sessions, windows, and panes in the current tmux server.
- Ignores ordinary shells, editors, and other foreground commands.
- Inspects only the pane's visible screen; it does not read scrollback or save captured text.
- Marks Agents with a supported working footer as Running.
- Marks supported approvals and questions as Needs attention.
- Changes a Running Agent that finishes in the background to Needs attention, while a selected completion becomes Stale.
- Changes a Reviewable result to Stale after its pane is selected. Selecting an Input request acknowledges it temporarily; it returns to Needs attention if the user leaves without responding.
- Marks a first-discovered background idle Agent as Unknown and a selected idle Agent as Stale.
- Changes an Unknown idle Agent to Stale after it is selected and scanned.
- Keeps unsupported or ambiguous Agent screens Unknown instead of guessing their state.
- Stores Agent metadata on the pane, so no runtime state files are created.
- Keeps five numeric count options available, including zero values.
- Refreshes status-driven scans asynchronously, retaining the previous widget while the next scan runs.
- Provides an explicitly placed `#{tmux_agents}` status placeholder with a robot icon, a conditional orange Needs attention pill, a conditional green Running count, a conditional yellow Unknown count, and a muted Stale count.

## Requirements

- tmux 3.2 or newer
- Bash, with runtime scripts compatible with Bash 3.2
- A Nerd Font for the robot icon

Contributors also need Bats and ShellCheck.

## Install with TPM

Add tmux-agents and place its widget in `tmux.conf` before TPM is initialized:

```tmux
set -g @plugin 'twstddev/tmux-agents'
set -g status-interval 2
set -ag status-right ' #{tmux_agents}'
```

Press prefix + <kbd>I</kbd> to install it. The plugin replaces only an explicitly configured placeholder and does not otherwise change status-bar placement.

## Install manually

Clone the plugin into the standard tmux plugin directory:

```sh
git clone https://github.com/twstddev/tmux-agents ~/.tmux/plugins/tmux-agents
```

Then add the widget and plugin entry point to `tmux.conf`:

```tmux
set -g status-interval 2
set -ag status-right ' #{tmux_agents}'
run-shell ~/.tmux/plugins/tmux-agents/tmux-agents.tmux
```

Reload `tmux.conf` to start tracking Agents. The plugin replaces only the placeholder shown above and does not otherwise change status-bar placement.

## Public count options

The following global tmux user options always contain numeric values:

- `@tmux_agents_count_attention`
- `@tmux_agents_count_running`
- `@tmux_agents_count_unknown`
- `@tmux_agents_count_stale`
- `@tmux_agents_count_total`

All five options reflect each completed scan. The four state counts are mutually exclusive and sum to the total.

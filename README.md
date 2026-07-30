# tmux-agents

A lightweight tmux plugin for tracking Codex and Claude Code agents across sessions.

The project is being built in small, usable slices. The current version recognizes a selected Codex pane showing the supported idle prompt, marks it as Stale, and exposes that state through tmux options and a compact status widget.

## Current capabilities

- Discovers a foreground `codex` process in the selected pane.
- Inspects only the pane's visible screen; it does not read scrollback or save captured text.
- Marks a recognized idle Codex Agent as Stale.
- Stores Agent metadata on the pane, so no runtime state files are created.
- Keeps five numeric count options available, including zero values.
- Provides an explicitly placed `#{tmux_agents}` status placeholder with a robot icon and muted Stale count.

Claude Code discovery, additional Agent states, navigation, and the chooser are planned but are not implemented yet.

## Requirements

- tmux 3.2 or newer
- Bash, with runtime scripts compatible with Bash 3.2
- A Nerd Font for the robot icon

Contributors also need Bats and ShellCheck.

## Install with TPM

Add tmux-agents and place its widget in `tmux.conf` before TPM is initialized:

```tmux
set -g @plugin 'twstddev/tmux-agents'
set -ag status-right ' #{tmux_agents}'
```

Press prefix + <kbd>I</kbd> to install it. The plugin replaces only an explicitly configured placeholder and does not otherwise change status-bar placement.

## Test a local checkout

TPM remains the normal installation path. To test changes from a local checkout, temporarily disable the `twstddev/tmux-agents` TPM declaration so the plugin is not loaded twice.

Add `#{tmux_agents}` to the final `status-right` definition, after any theme or styling file that replaces it, then load the local entry point immediately afterward:

```tmux
set -g status-right '#{tmux_agents} %H:%M'
run-shell /absolute/path/to/tmux-agents/tmux-agents.tmux
```

Replace the example status value with your existing status styling, keeping the `#{tmux_agents}` placeholder. Reload `tmux.conf` after each local change.

## Public count options

The following global tmux user options always contain numeric values:

- `@tmux_agents_count_attention`
- `@tmux_agents_count_running`
- `@tmux_agents_count_unknown`
- `@tmux_agents_count_stale`
- `@tmux_agents_count_total`

Only Stale classification is implemented in the current slice, so the other state counts remain zero.

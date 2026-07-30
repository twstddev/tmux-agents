# tmux-agents

A lightweight tmux plugin for tracking Codex and Claude Code agents across sessions.

It discovers idle Codex and Claude Code panes across the current tmux server and shows whether their earlier output has been acknowledged.

## Current capabilities

- Discovers foreground `codex` and `claude` processes across all sessions, windows, and panes in the current tmux server.
- Ignores ordinary shells, editors, and other foreground commands.
- Inspects only the pane's visible screen; it does not read scrollback or save captured text.
- Marks a first-discovered background idle Agent as Unknown and a selected idle Agent as Stale.
- Changes an Unknown idle Agent to Stale after it is selected and scanned.
- Stores Agent metadata on the pane, so no runtime state files are created.
- Keeps five numeric count options available, including zero values.
- Provides an explicitly placed `#{tmux_agents}` status placeholder with a robot icon, a conditional yellow Unknown count, and a muted Stale count.

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

Idle Agents are classified as Unknown or Stale. The Needs attention and Running count options report zero.

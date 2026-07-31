# tmux-agents

A lightweight tmux plugin for tracking Codex and Claude Code agents across sessions.

It discovers Codex and Claude Code panes across the current tmux server and classifies them as Needs attention, Running, or Stale.

## Current capabilities

- Discovers `codex` and `claude` processes anywhere below a pane across all sessions, windows, and panes in the current tmux server.
- Recognizes Agents below ordinary wrapper and editor processes while ignoring panes with no supported Agent process.
- Inspects only the pane's visible screen; it does not read scrollback or save captured text.
- Marks Agents with a supported working footer as Running.
- Marks supported approvals and questions as Needs attention.
- Changes a Running Agent that finishes in the background to Needs attention, while a selected completion becomes Stale.
- Changes a Reviewable result to Stale after its pane is selected. Selecting an Input request acknowledges it temporarily; it returns to Needs attention if the user leaves without responding.
- Marks idle, unsupported, and ambiguous Agent screens as Stale when no Running or Needs attention signal is detected.
- Supports optional Codex and Claude Code lifecycle hooks for immediate standalone Agent updates.
- Stores Agent metadata on the pane, so no runtime state files are created.
- Keeps four numeric count options available, including zero values.
- Refreshes status-driven scans asynchronously, retaining the previous widget while the next scan runs.
- Provides an explicitly placed `#{tmux_agents}` status placeholder with a robot icon, a conditional orange Needs attention pill, a conditional green Running count, and a muted Stale count.
- Opens an fzf Agent chooser with prefix + <kbd>A</kbd>. The chooser groups Agents by Needs attention, Stale, then Running; shows pane context and state age; previews the highlighted pane's current screen; and can switch the invoking client across sessions.
- Jumps directly to the longest-waiting Agent that Needs attention with prefix + <kbd>a</kbd>.

## Requirements

- tmux 3.3 or newer
- Bash 3.2 or newer
- fzf 0.61.3 or newer for the Agent chooser
- A Nerd Font for the default robot icon

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

## Enable lifecycle hooks

Lifecycle hooks are optional. When configured, a standalone Codex or Claude Code Agent reports session start, work, input requests, results, and normal session end directly to tmux-agents. This makes state updates immediate and keeps hook-reported state from being replaced by unrecognized visible output. The existing visible-screen detection remains available for Agents without hooks.

Hooks must run in a tmux pane. The hook command safely does nothing outside tmux, and it records only the Agent type, state, session and turn identifiers, and timestamps—never the hook's prompt, tool input, or conversation text.

Replace `/absolute/path/to/tmux-agents` below with the directory where you installed this plugin. Add the following configuration to `~/.codex/hooks.json` for Codex:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex start" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex running" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex running" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex input" }] }],
    "PreToolUse": [{ "matcher": "request_user_input", "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex input" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex result" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh codex end" }] }]
  }
}
```

Codex requires you to review and trust non-managed command hooks before it runs them. Use `/hooks` in Codex after saving the file to review and trust these commands. tmux-agents never edits or trusts Codex configuration on your behalf.

Add the equivalent user-wide configuration to `~/.claude/settings.json` for Claude Code:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude start" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude running" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude running" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude input" }] }],
    "PreToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude input" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude result" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/absolute/path/to/tmux-agents/scripts/hook.sh claude end" }] }]
  }
}
```

Claude Code merges user hooks with project and managed configuration. Review the final hook configuration with its `/hooks` command before relying on it.

## Debug lifecycle tracking

To trace lifecycle events and scanning decisions, enable the opt-in tmux message log:

```tmux
set -g @tmux_agents_debug 1
```

Inspect it with `tmux show-messages | grep 'tmux-agents debug'`. Messages are emitted only for scan-driven state changes and option updates. They never include visible screen text, prompts, tool input, or conversation content. Disable the trace with `set -gu @tmux_agents_debug`.

## Customize the status widget

The default `#{tmux_agents}` widget shows the robot icon, followed by Needs attention, Running, and Stale. Needs attention and Running disappear when their count is zero; Stale remains visible so the widget has a stable presence.

For custom styling, add the zero-width `#{tmux_agents_scan}` trigger and render any of the public count options yourself. The trigger refreshes the counts asynchronously without adding text:

```tmux
set -g status-interval 2
set -ag status-right ' #{tmux_agents_scan}A:#{@tmux_agents_count_attention} R:#{@tmux_agents_count_running} S:#{@tmux_agents_count_stale}'
```

Set either placeholder before the plugin entry point runs. The plugin does not add a placeholder or change `status-left` or `status-right` on its own.

## Browse Agents

Press prefix + <kbd>A</kbd> to open the Agent chooser. It appears immediately with a loading row while it performs a fresh Agent scan. Needs attention Agents then appear first, with the longest-waiting request at the top. Stale and Running Agents follow. Typing uses normal fzf relevance sorting.

Each entry shows its state, Agent type, tmux location, working directory, and state age. A useful Agent title appears on a separate first line. The right-side preview reads only the highlighted pane's current visible screen and preserves its colors and text attributes.

Select an entry to switch the client that opened the chooser to that Agent. Selecting an Agent also acknowledges it in the same way as ordinary tmux navigation.

Set `@tmux_agents_chooser_key` before loading the plugin to change the default uppercase <kbd>A</kbd> binding:

```tmux
set -g @tmux_agents_chooser_key 'G'
```

## Jump through Needs attention

Press prefix + <kbd>a</kbd> to refresh Agent state and switch directly to the longest-waiting Agent that Needs attention. Repeating the shortcut moves through Reviewable results from oldest to newest as each result is acknowledged. If no Agent needs attention, tmux shows a short message and leaves you in place.

Set `@tmux_agents_jump_key` before loading the plugin to change the default lowercase <kbd>a</kbd> binding:

```tmux
set -g @tmux_agents_jump_key 'g'
```

## Public count options

The following global tmux user options always contain numeric values:

- `@tmux_agents_count_attention`
- `@tmux_agents_count_running`
- `@tmux_agents_count_stale`
- `@tmux_agents_count_total`

All four options reflect each completed scan. The three state counts are mutually exclusive and sum to the total.

## Detection and privacy limits

- Detection recognizes the current English Codex and Claude Code TUI layouts. Agents using customized, translated, or newly changed layouts are treated as Stale unless a Running or Needs attention signal is recognized.
- Discovery follows each pane's process tree to find `codex` and `claude` descendants. One Agent is represented per pane; unsupported processes do not create an Agent entry.
- Discovery covers every pane in the current tmux server, but does not cross into a separate tmux socket server, remote host, or nested tmux instance.
- Classification is passive screen inference. tmux-agents does not configure lifecycle hooks, terminal bells, or either Agent CLI.
- Each scan captures only the visible screen grid. It does not request scrollback, read transcripts, or persist captured text. Pane-scoped metadata contains Agent type, state and transition time, attention and acknowledgment data, detector evidence, and a non-reversible screen signature. It disappears when the pane closes.

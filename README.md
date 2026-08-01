# tmux-agents

A lightweight tmux plugin for tracking Codex and Claude Code agents across sessions.

It discovers Codex and Claude Code panes across the current tmux server and classifies them as Needs attention, Running, or Stale.

## Current capabilities

- Discovers `codex` and `claude` processes anywhere below a pane across all sessions, windows, and panes in the current tmux server.
- Recognizes Agents below ordinary wrapper and editor processes while ignoring panes with no supported Agent process.
- Uses lifecycle hooks as the preferred source of state and updates the status immediately when a hook arrives.
- Coexists with existing tmux pane-selection and pane-exit hooks instead of replacing them.
- Gives a newly discovered Agent a short hook grace period, then checks only hook-unavailable panes every two seconds using their visible screen.
- Reconciles the process tree when the plugin loads, before chooser and jump navigation, and as a 60-second safety check. The interval is configurable with `@tmux_agents_safety_interval`.
- Keeps hook-driven status changes, chooser population, and direct jumps responsive as unrelated panes grow.
- Inspects only fallback panes' visible screens; it does not read scrollback or save captured text.
- Marks fallback Agents with a supported working footer as Running and supported approvals and questions as Needs attention.
- Changes a Reviewable result to Stale after its pane is selected. Selecting an Input request acknowledges it temporarily; it returns to Needs attention if the user leaves without responding.
- Marks idle, unsupported, and ambiguous Agent screens as Stale when no Running or Needs attention signal is detected.
- Supports optional Codex and Claude Code lifecycle hooks for immediate standalone Agent updates.
- Verifies Sidekick's embedded Codex and Claude Code terminals through Neovim RPC, including hookless Agents discovered below Neovim, then returns navigation to the containing editor pane and opens the Agent in Sidekick's configured layout.
- Stores Agent metadata on the pane, so no runtime state files are created.
- Keeps four numeric count options available, including zero values.
- Keeps status rendering event-driven: the widget reads cached tmux options and never starts process discovery or captures a screen.
- Provides an explicitly placed `#{tmux_agents}` status placeholder with a robot icon, a conditional orange Needs attention pill, a conditional green Running count, and a muted Stale count.
- Opens an fzf Agent chooser with prefix + <kbd>A</kbd>. The chooser groups Agents by Needs attention, Stale, then Running; marks embedded Sidekick Agents; shows pane context and state age; previews the highlighted pane's current screen; and can switch the invoking client across sessions.
- Jumps directly to the longest-waiting Agent that Needs attention with prefix + <kbd>a</kbd>.
- Provides a diagnostic command for process discovery, hook registration, fallback state, and Sidekick RPC readiness without inspecting Agent conversations.

## Requirements

- tmux 3.3 or newer
- Bash 3.2 or newer
- fzf 0.61.3 or newer for the Agent chooser
- Neovim with [sidekick.nvim](https://github.com/folke/sidekick.nvim) for embedded Sidekick Agent navigation
- A Nerd Font for the default robot icon

## Install with TPM

Add tmux-agents and place its widget in `tmux.conf` before TPM is initialized:

```tmux
set -g @plugin 'twstddev/tmux-agents'
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
set -ag status-right ' #{tmux_agents}'
run-shell ~/.tmux/plugins/tmux-agents/tmux-agents.tmux
```

Reload `tmux.conf` to start tracking Agents. The plugin replaces only the placeholder shown above and does not otherwise change status-bar placement.

## Enable lifecycle hooks

Lifecycle hooks are optional. When configured, a standalone Codex or Claude Code Agent reports session start, work, input requests, results, and normal session end directly to tmux-agents. This makes state updates immediate and keeps hook-reported state from being replaced by unrecognized visible output. When the hook runs in Sidekick's embedded terminal, tmux-agents also verifies the host through Neovim RPC. Agents without a working registration fall back to visible-screen detection after a short grace period.

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

Hook registration is always manual. tmux-agents never edits either Agent's configuration and never approves or trusts hook commands for you.

## Diagnose tracking

Run the diagnostic command from a tmux pane when an Agent is missing, stuck in fallback, or unable to reopen through Sidekick:

```sh
~/.tmux/plugins/tmux-agents/scripts/diagnose.sh
```

Use the actual installation path if you installed the plugin elsewhere. The command performs a fresh process-tree reconciliation, then prints one line for every supported Agent process with its tmux pane, Agent type and process ID, hook registration, last hook activity, identity, state source, fallback status, and Sidekick host and RPC status. An Agent without a pane in the current tmux server is reported as untracked with an action to run diagnostics in its containing server or restart it inside tmux.

`hook=healthy` means the pane has a valid hook registration; `last-hook-activity` reports the last accepted event as a Unix timestamp. Silence alone never changes a hook to unhealthy because a long-running turn and a silent hook cannot be distinguished from elapsed time. `missing-startup-hook` is still in the startup grace period, while `fallback=active` means visible-screen checks are running every two seconds. Sidekick diagnostics distinguish a verified host, a reachable Neovim instance that does not expose the supported embedded Sidekick terminal, and an RPC failure whose address may be stale. They report unavailable RPC tooling and unexpected responses separately instead of assuming the address is stale.

Diagnostics inspect process metadata, pane-scoped tmux options, and non-content Neovim integration state. They do not capture pane screens or request hidden terminal lines, scrollback, transcripts, prompts, or tool input.

## Debug lifecycle tracking

To trace lifecycle events and scanning decisions, enable the opt-in tmux message log:

```tmux
set -g @tmux_agents_debug 1
```

Inspect it with `tmux show-messages | grep 'tmux-agents debug'`. Messages are emitted only for scan-driven state changes and option updates. They never include visible screen text, prompts, tool input, or conversation content. Disable the trace with `set -gu @tmux_agents_debug`.

## Customize the status widget

The default `#{tmux_agents}` widget shows the robot icon, followed by Needs attention, Running, and Stale. Needs attention and Running disappear when their count is zero; Stale remains visible so the widget has a stable presence. Rendering only reads its cached tmux option, so your normal `status-interval` does not control Agent discovery or polling.

For custom styling, render the public count options directly:

```tmux
set -ag status-right ' A:#{@tmux_agents_count_attention} R:#{@tmux_agents_count_running} S:#{@tmux_agents_count_stale}'
```

Set the default placeholder before the plugin entry point runs if you want the built-in widget. The plugin does not add a placeholder or change `status-left` or `status-right` on its own. The former `#{tmux_agents_scan}` placeholder has been removed.

## Browse Agents

Press prefix + <kbd>A</kbd> to open the Agent chooser. It appears immediately with a loading row while it reconciles Agent discovery before listing Agents. Needs attention Agents then appear first, with the longest-waiting request at the top. Stale and Running Agents follow. Typing uses normal fzf relevance sorting.

Each entry shows its state, Agent type, tmux location, working directory, and state age. Embedded Agents retain their Codex or Claude Code type and add a `Sidekick` marker. If a hidden embedded Agent is using passive fallback instead of valid hook state, the entry is Stale and shows `hook unavailable`; a visible terminal can still use visible-screen inference. A useful Agent title appears on a separate first line.

The right-side preview reads only the highlighted pane's current visible screen and preserves its colors and text attributes. When a Sidekick terminal is visible, it appears through that ordinary pane preview. When it is hidden, the preview shows the current Neovim pane with a notice that confirming the selection will open and focus the Agent. If the visibility check fails, the preview says that visibility is unavailable instead of claiming the Agent is hidden. Highlighting an entry checks only whether the Sidekick terminal window is open; it never opens or focuses Sidekick.

Select an entry to switch the client that opened the chooser to that Agent. Selecting an Agent also acknowledges it in the same way as ordinary tmux navigation. For a verified Sidekick Agent, the client switches to its Neovim pane and Sidekick shows and focuses the existing terminal without changing its configured float or split layout. If the Sidekick request fails, the client remains in the Neovim pane and receives a concise warning.

Set `@tmux_agents_chooser_key` before loading the plugin to change the default uppercase <kbd>A</kbd> binding:

```tmux
set -g @tmux_agents_chooser_key 'G'
```

## Jump through Needs attention

Press prefix + <kbd>a</kbd> to reconcile Agent discovery and switch directly to the longest-waiting Agent that Needs attention. Repeating the shortcut moves through Reviewable results from oldest to newest as each result is acknowledged. For a verified Sidekick Agent, the shortcut opens and focuses its Sidekick terminal after switching to the containing Neovim pane. If no Agent needs attention, tmux shows a short message and leaves you in place.

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

All four options are updated by hook, selection, pane-lifecycle, fallback, and reconciliation events. The three state counts are mutually exclusive and sum to the total.

## Detection and privacy limits

- Detection recognizes the current English Codex and Claude Code TUI layouts. Agents using customized, translated, or newly changed layouts are treated as Stale unless a Running or Needs attention signal is recognized.
- Discovery follows each pane's process tree to find `codex` and `claude` descendants. One Agent is represented per pane; unsupported processes do not create an Agent entry.
- A hook with an `NVIM` server address verifies that Sidekick owns one embedded terminal for the Agent type before recording it as a Sidekick Agent. For a hookless Agent discovered below Neovim, reconciliation reads only the Agent process's `NVIM` address from its environment and performs the same verification; other environment values are discarded and never stored. The RPC calls only inspect Sidekick host metadata and window visibility or request that terminal be shown and focused; they never read terminal lines, scrollback, or transcripts.
- Sidekick's embedded terminal backend is represented by its containing Neovim pane. Sidekick Agents launched in external tmux windows or splits are ordinary standalone Agent panes and are not redirected through Neovim.
- Discovery covers every pane in the current tmux server, but does not cross into a separate tmux socket server, remote host, or nested tmux instance.
- Hook events are preferred. An Agent without hook registration receives a short grace period and then is passively checked every two seconds. A valid hook event stops that pane's fallback polling immediately.
- A hook that registered and later becomes silent is not timed out based on age. A hidden embedded Sidekick Agent can therefore show its previous state until another hook event arrives or its integration is diagnosed; tmux-agents does not read the hidden terminal to guess a newer state.
- The 60-second safety reconciliation catches Agent processes that ended without reporting a normal session end, so an unreported shutdown can remain visible for up to that interval. Set `@tmux_agents_safety_interval` before loading the plugin to choose another positive number of seconds.
- Tmux pane selection acknowledges attention without waiting for a scan, and pane lifecycle events refresh the counts after a close.
- tmux-agents does not configure lifecycle hooks, terminal bells, or either Agent CLI automatically.
- Fallback checks capture only the visible screen grid. They do not request scrollback, read transcripts, or persist captured text. Pane-scoped metadata contains Agent type, identity, state and transition time, last hook activity, attention and acknowledgment data, detector evidence, host integration facts, and a non-reversible screen signature. It disappears when the pane closes.

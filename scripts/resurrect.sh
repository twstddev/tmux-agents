#!/bin/sh

set -eu

snapshot=${1-}
[ -f "$snapshot" ] || exit 0

temporary_file=$(mktemp "${snapshot}.agents.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT
trap 'exit 1' HUP INT TERM

tab=$(printf '\t')
pane_format="#{session_name}${tab}#{window_index}${tab}#{pane_index}${tab}#{pane_current_command}${tab}#{@tmux_agents_resume_command}"
panes=$(tmux list-panes -a -F "$pane_format")

printf '%s\n' "$panes" | awk -F '\t' '
  BEGIN { OFS = "\t" }
  FILENAME == "-" {
    if (($4 == "codex" && $5 ~ /^codex resume [A-Za-z0-9_][A-Za-z0-9_-]*$/) ||
        ($4 == "claude" && $5 ~ /^claude --resume [A-Za-z0-9_][A-Za-z0-9_-]*$/)) {
      resume[$1, $2, $3, $4] = $5
    }
    next
  }
  function popup(name) { return name ~ /^__agent_popup_[0-9]+$/ }
  ($1 == "pane" || $1 == "window" || $1 == "grouped_session") && popup($2) { next }
  $1 == "grouped_session" && popup($3) { next }
  $1 == "state" {
    if (popup($2)) $2 = ""
    if (popup($3)) $3 = ""
  }
  $1 == "pane" && NF == 11 {
    command = resume[$2, $3, $6, $10]
    if (command != "") $11 = ":" command
  }
  { print }
' - "$snapshot" > "$temporary_file"

mv -f "$temporary_file" "$snapshot"

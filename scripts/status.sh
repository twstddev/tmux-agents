#!/bin/sh

set -eu

attention_count=0

while IFS='|' read -r pane_id pane_dead attention_marker; do
  [ -n "$pane_id" ] || continue
  [ "$pane_dead" = '0' ] || continue
  [ -n "$attention_marker" ] || continue
  attention_count=$((attention_count + 1))
done <<EOF
$(tmux list-panes -a -F '#{pane_id}|#{pane_dead}|#{@tmux_agents_attention}')
EOF

attention_status=
if [ "$attention_count" -gt 0 ]; then
  attention_fg=$(tmux show-options -gqv '@tmux_agents_attention_fg')
  attention_bg=$(tmux show-options -gqv '@tmux_agents_attention_bg')
  [ -n "$attention_fg" ] || attention_fg=white
  [ -n "$attention_bg" ] || attention_bg=red
  attention_status="#[fg=$attention_bg,bold]#[fg=$attention_fg,bg=$attention_bg,bold]󱙺 $attention_count#[fg=$attention_bg,bg=default,nobold]"
fi

tmux set-option -gq '@tmux_agents_status' "$attention_status"
tmux refresh-client -S 2>/dev/null || true

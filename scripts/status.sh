#!/bin/sh

set -eu

attention_count=0
finished_count=0

while IFS='|' read -r pane_id pane_dead attention_marker finished_marker; do
  [ -n "$pane_id" ] || continue
  [ "$pane_dead" = '0' ] || continue
  [ -n "$attention_marker" ] && attention_count=$((attention_count + 1))
  [ -n "$finished_marker" ] && finished_count=$((finished_count + 1))
done <<EOF
$(tmux list-panes -a -F '#{pane_id}|#{pane_dead}|#{@tmux_agents_attention}|#{@tmux_agents_finished}')
EOF

attention_status=
if [ "$attention_count" -gt 0 ]; then
  attention_fg=$(tmux show-options -gqv '@tmux_agents_attention_fg')
  attention_bg=$(tmux show-options -gqv '@tmux_agents_attention_bg')
  [ -n "$attention_fg" ] || attention_fg=white
  [ -n "$attention_bg" ] || attention_bg=red
  attention_status="#[fg=$attention_bg,bold]#[fg=$attention_fg,bg=$attention_bg,bold]󱙺 $attention_count#[fg=$attention_bg,bg=default,nobold]"
fi

finished_status=
if [ "$finished_count" -gt 0 ]; then
  finished_fg=$(tmux show-options -gqv '@tmux_agents_finished_fg')
  [ -n "$finished_fg" ] || finished_fg=green
  finished_status="#[fg=$finished_fg]󱜚 $finished_count"
fi

if [ -n "$attention_status" ] && [ -n "$finished_status" ]; then
  combined_status="$attention_status  $finished_status"
else
  combined_status="$attention_status$finished_status"
fi

tmux set-option -gq '@tmux_agents_status' "$combined_status"
tmux refresh-client -S 2>/dev/null || true

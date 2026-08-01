#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=${1-}

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"

state_begin_reconciliation
while IFS='|' read -r pane_id pane_state pane_type pane_source pane_identity \
  _pane_process_identity pane_evidence _pane_state_since attention_evidence \
  attention_signature acknowledged_signature _fallback_after _pane_host \
  _pane_nvim_server; do

  [ "$pane_state" = 'attention' ] || continue
  [ -n "$pane_type" ] || continue

  if [ "$pane_id" = "$selected_pane" ]; then
    case "$attention_evidence" in
    input)
      state_apply_event_if_current "$pane_id" "$pane_source" "$pane_identity" \
        "$pane_state" "$attention_signature" "$acknowledged_signature" \
        acknowledge "$pane_id" "$pane_type" 'attention' 'input' \
        "$attention_signature" "$pane_source" "$pane_identity" "$pane_evidence"
      ;;
    result)
      state_apply_event_if_current "$pane_id" "$pane_source" "$pane_identity" \
        "$pane_state" "$attention_signature" "$acknowledged_signature" \
        acknowledge "$pane_id" "$pane_type" 'stale' 'result' \
        "$attention_signature" "$pane_source" "$pane_identity" "$pane_evidence"
      ;;
    esac
  elif [ "$attention_evidence" = 'input' ] &&
    [ "$acknowledged_signature" = "$attention_signature" ]; then
    state_apply_event_if_current "$pane_id" "$pane_source" "$pane_identity" \
      "$pane_state" "$attention_signature" "$acknowledged_signature" \
      transition "$pane_id" "$pane_type" 'attention' 'input' \
      "$attention_signature" '' "$pane_source" "$pane_identity" "$pane_evidence"
  fi
done < <(pane_tracking_snapshot)
state_end_reconciliation

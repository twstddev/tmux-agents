#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ -z "${TMUX-}" ]; then
  printf '%s\n' 'tmux-agents: diagnostics must run inside tmux' >&2
  exit 1
fi

"$plugin_root/scripts/reconcile.sh" --diagnostics

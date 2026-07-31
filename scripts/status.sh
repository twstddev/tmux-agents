#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
selected_pane=$1

"$plugin_root/scripts/scan.sh" "$selected_pane"

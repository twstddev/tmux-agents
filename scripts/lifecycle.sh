#!/usr/bin/env bash

set -e

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source-path=SCRIPTDIR
# shellcheck source=state.sh
. "$plugin_root/scripts/state.sh"

state_refresh

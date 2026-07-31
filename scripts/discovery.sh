#!/usr/bin/env bash

# Process-tree discovery for reconciliation scans.

discovery_capture_process_snapshot() {
  process_snapshot=$(ps -axo pid=,ppid=,comm=)
}

discovery_find_agent_descendant() {
  discovery_root_pid=$1

  printf '%s\n' "$process_snapshot" | awk -v root_pid="$discovery_root_pid" '
    {
      process_pid = $1
      process_parent_pid = $2
      process_command = $3
      process_name[process_pid] = process_command
      children[process_parent_pid] = children[process_parent_pid] " " process_pid
    }

    function agent_type(process_id, name) {
      name = process_name[process_id]
      sub(/^.*\//, "", name)
      if (name == "codex" || name == "claude") {
        return name
      }
      return ""
    }

    function find_descendant(process_id, child_ids, child_count, child_index, child_id, type) {
      type = agent_type(process_id)
      if (type != "") {
        printf "%s|pid:%s\n", type, process_id
        return 1
      }

      child_count = split(children[process_id], child_ids, " ")
      for (child_index = 1; child_index <= child_count; child_index++) {
        child_id = child_ids[child_index]
        if (child_id != "" && find_descendant(child_id)) {
          return 1
        }
      }
      return 0
    }

    END { find_descendant(root_pid) }
  '
}

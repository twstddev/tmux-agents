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

    function process_basename(process_id, name) {
      name = process_name[process_id]
      sub(/^.*\//, "", name)
      return name
    }

    function agent_type(process_id, name) {
      name = process_basename(process_id)
      if (name == "codex" || name == "claude") {
        return name
      }
      return ""
    }

    function find_descendant(process_id, nvim_process_id, child_ids, child_count, child_index, child_id, type) {
      if (process_basename(process_id) == "nvim") {
        nvim_process_id = process_id
      }

      type = agent_type(process_id)
      if (type != "") {
        printf "%s|pid:%s|%s\n", type, process_id, nvim_process_id
        return 1
      }

      child_count = split(children[process_id], child_ids, " ")
      for (child_index = 1; child_index <= child_count; child_index++) {
        child_id = child_ids[child_index]
        if (child_id != "" && find_descendant(child_id, nvim_process_id)) {
          return 1
        }
      }
      return 0
    }

    END { find_descendant(root_pid) }
  '
}

discovery_capture_agent_environments() {
  discovery_agent_pids=$1
  process_environment_snapshot=
  discovery_ps_pids=
  discovery_previous_ifs=$IFS
  IFS=','

  for discovery_agent_pid in $discovery_agent_pids; do
    if [ -r "/proc/$discovery_agent_pid/environ" ]; then
      discovery_nvim_server=$(tr '\0' '\n' \
        <"/proc/$discovery_agent_pid/environ" | awk '
          /^NVIM=/ {
            sub(/^NVIM=/, "")
            print
            exit
          }
        ')
      if [ -n "$discovery_nvim_server" ]; then
        process_environment_snapshot="${process_environment_snapshot}${discovery_agent_pid} NVIM=${discovery_nvim_server}
"
      fi
    elif [ -z "$discovery_ps_pids" ]; then
      discovery_ps_pids=$discovery_agent_pid
    else
      discovery_ps_pids="$discovery_ps_pids,$discovery_agent_pid"
    fi
  done
  IFS=$discovery_previous_ifs

  if [ -n "$discovery_ps_pids" ]; then
    discovery_ps_environment=$(ps eww -p "$discovery_ps_pids" \
      -o pid=,command= 2>/dev/null | awk '
        {
          process_id = $1
          for (field_index = 2; field_index <= NF; field_index++) {
            if ($field_index ~ /^NVIM=/) {
              print process_id, $field_index
              break
            }
          }
        }
      ' || true)
    if [ -n "$discovery_ps_environment" ]; then
      process_environment_snapshot="${process_environment_snapshot}${discovery_ps_environment}
"
    fi
  fi
}

discovery_find_nvim_server() {
  discovery_agent_pid=$1

  printf '%s\n' "$process_environment_snapshot" | awk \
    -v agent_pid="$discovery_agent_pid" '
      $1 == agent_pid {
        for (field_index = 2; field_index <= NF; field_index++) {
          if ($field_index ~ /^NVIM=/) {
            sub(/^NVIM=/, "", $field_index)
            print $field_index
            exit
          }
        }
      }
    '
}

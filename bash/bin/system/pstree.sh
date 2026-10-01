#!/usr/bin/env bash
# Show process ancestry/tree without unnecessary privilege escalation.
set -u
set -o pipefail

PID="${1:-}"
[[ "$PID" == -h || "$PID" == --help ]] && { printf 'Usage: pstree-info <PID>\n'; exit 0; }
[[ "$PID" =~ ^[0-9]+$ ]] || { printf 'Usage: pstree-info <PID>\n' >&2; exit 2; }
[[ -d "/proc/$PID" ]] || { printf 'PID %s does not exist.\n' "$PID" >&2; exit 1; }

printf 'Process details\n--------------------------------------------------------------------------------\n'
ps -p "$PID" -o pid,ppid,user,stat,etimes,%cpu,%mem,args 2>/dev/null || true
printf '\nProcess ancestry / descendants\n--------------------------------------------------------------------------------\n'
if command -v pstree >/dev/null 2>&1; then
    pstree -aps "$PID" 2>/dev/null || pstree -ap "$PID" 2>/dev/null || true
else
    printf 'pstree is unavailable; ancestry from ps:\n'
    current="$PID"
    while [[ "$current" =~ ^[0-9]+$ && "$current" -gt 1 ]]; do
        ps -p "$current" -o pid=,ppid=,user=,args= 2>/dev/null || break
        current="$(ps -p "$current" -o ppid= 2>/dev/null | tr -d ' ')"
    done
fi

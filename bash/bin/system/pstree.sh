#!/usr/bin/env bash
set -euo pipefail

# Display usage instructions
show_help() {
  cat <<EOF
Command usage:
  ./ps_tree.sh <PID>
  ./ps_tree.sh -h | --help
EOF
}

# 1. Check if at least one argument was provided
if [[ $# -eq 0 ]]; then
  echo "Error: A PID is required." >&2
  show_help
  exit 1
fi

# 2. Handle the help flag (accessible without root privileges)
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# 3. Elevate privileges using sudo if not running as root (EUID != 0)
if [[ $EUID -ne 0 ]]; then
  echo "[+] Re-running with administrator privileges (sudo)..." >&2
  exec sudo "$0" "$@"
fi

ROOT_PID="$1"

# 4. Validate that the ROOT_PID is a valid numerical integer
if ! [[ "$ROOT_PID" =~ ^[0-9]+$ ]]; then
  echo "Error: PID '$ROOT_PID' must be a valid integer." >&2
  exit 1
fi

# 5. Check process existence directly in /proc filesystem
if [[ ! -d "/proc/$ROOT_PID" ]]; then
  echo "Error: Process with PID $ROOT_PID does not exist." >&2
  exit 1
fi

# 6. Extract child PIDs excluding threads (-T) and using ASCII formatting (-A)
PIDS=$(pstree -p -T -A "$ROOT_PID" 2>/dev/null | grep -oP '\(\K[0-9]+(?=\))' | tr '\n' ',' | sed 's/,$//')

# 7. Display the process hierarchy using ps
if [[ -n "$PIDS" ]]; then
  ps -f -H -p "$PIDS"
else
  ps -f -p "$ROOT_PID"
fi
#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<EOF
Uso del comando:
  ./ps_tree.sh <PID>
  ./ps_tree.sh -h | --help
EOF
}

if [[ $# -eq 0 ]]; then
  echo "Error: Se requiere un PID." >&2
  show_help
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "[+] Reejecutando con permisos de administrador (sudo)..." >&2
  exec sudo "$0" "$@"
fi

ROOT_PID="$1"

if ! [[ "$ROOT_PID" =~ ^[0-9]+$ ]]; then
  echo "Error: El PID '$ROOT_PID' debe ser un número entero válido." >&2
  exit 1
fi

if [[ ! -d "/proc/$ROOT_PID" ]]; then
  echo "Error: El proceso con PID $ROOT_PID no existe." >&2
  exit 1
fi

PIDS=$(pstree -p -T -A "$ROOT_PID" 2>/dev/null | grep -oP '\(\K[0-9]+(?=\))' | tr '\n' ',' | sed 's/,$//')

if [[ -n "$PIDS" ]]; then
  ps -f -H -p "$PIDS"
else
  ps -f -p "$ROOT_PID"
fi
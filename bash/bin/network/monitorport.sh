#!/usr/bin/env bash

# Restore terminal cursor and reset color formatting on exit (SIGINT/SIGTERM)
trap 'tput cnorm 2>/dev/null; printf "\e[0m\n"; exit 1' INT TERM

# Validate required arguments (Host and Port) or display help
if [[ "$1" == "-h" || -z "$1" || -z "$2" ]]; then
  cat <<'EOF'
SUMMARY:
--------
This script will monitor a port UNTIL it becomes available.

USAGE:
------
monitorPort.sh [hostname] [port_number] [interval_seconds]
monitorPort.sh google.com 443
monitorPort.sh 127.0.0.1 8080 2

Version 1.1.0
EOF
  exit 0
fi

HOST="$1"
PORT="$2"
INTERVAL="${3:-1}"
ctr=1

# Hide terminal cursor during operation
tput civis 2>/dev/null

printf "\e[33mMonitoring %s:%s...\e[0m\n" "$HOST" "$PORT"

# Poll target host and port until connection succeeds
while ! nc -z -w 1 "$HOST" "$PORT" &> /dev/null; do
  printf "\r\e[31mWaiting for %s:%s (#%d)...\e[0m\e[K" "$HOST" "$PORT" "$ctr"
  ((ctr++))
  sleep "$INTERVAL"
done

# Restore terminal cursor on success
tput cnorm 2>/dev/null

printf "\r\e[32m[SUCCESS] %s:%s is now reachable! (#%d)\e[0m\e[K\n" "$HOST" "$PORT" "$ctr"
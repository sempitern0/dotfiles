#!/usr/bin/env bash
# OBJECTIVE: Audit open local listening ports and mapped binaries.
set -euo pipefail

echo -e "\n[+] Open Listening Ports & Mapped Processes"
echo "----------------------------------------------------------------------"
printf "%-10s %-10s %-25s %-20s\n" "PROTO" "PORT" "LISTEN ADDR" "PROCESS (PID)"
echo "----------------------------------------------------------------------"

ss -tulpn | awk 'NR>1 {
    proto=$1; local=$5; proc=$7;
    split(local, a, ":"); port=a[length(a)];
    sub(":"port, "", local);
    printf "%-10s %-10s %-25s %-20s\n", proto, port, local, proc
}'
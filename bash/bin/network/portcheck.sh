#!/usr/bin/env bash
# Display local listening sockets using iproute2's ss output (IPv4 and IPv6 safe).
set -u
set -o pipefail

command -v ss >/dev/null 2>&1 || { printf 'ss (iproute2) is required.\n' >&2; exit 1; }
echo "Listening TCP/UDP sockets"
echo "--------------------------------------------------------------------------------"
if (( EUID == 0 )); then
    ss -H -lntup 2>/dev/null || ss -H -lntu
else
    ss -H -lntup 2>/dev/null || ss -H -lntu
    echo
    echo "Tip: run with sudo if process/PID information is hidden by the kernel."
fi

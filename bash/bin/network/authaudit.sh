#!/usr/bin/env bash
# OBJECTIVE: Parse system journal for authentication events and SSH failures.
set -euo pipefail

echo -e "\n[+] Recent Failed SSH Login Attempts"
echo "----------------------------------------------------------------------"
journalctl -u ssh -u sshd --no-pager -n 50 2>/dev/null | grep -E "Failed password|Invalid user" | tail -n 10 || echo "No recent SSH failures."

echo -e "\n[+] Recent Sudo Executions"
echo "----------------------------------------------------------------------"
journalctl _COMM=sudo --no-pager -n 10 2>/dev/null | grep COMMAND | tail -n 10 || echo "No recent sudo activity."
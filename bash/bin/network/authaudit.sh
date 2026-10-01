#!/usr/bin/env bash
# Summarize recent authentication activity from systemd-journald.
set -u
set -o pipefail

HOURS="${1:-24}"
[[ "$HOURS" =~ ^[0-9]+$ ]] || { printf 'Usage: authaudit [hours]\n' >&2; exit 2; }
command -v journalctl >/dev/null 2>&1 || { printf 'journalctl is not available.\n' >&2; exit 1; }

SINCE="${HOURS} hours ago"

echo
echo "SSH authentication events — last ${HOURS}h"
echo "--------------------------------------------------------------------------------"
journalctl --since "$SINCE" -u ssh.service -u sshd.service --no-pager -o short-iso 2>/dev/null |
    grep -Ei 'Accepted |Failed |Invalid user|authentication failure|Connection closed by authenticating user' |
    tail -n 40 || true

echo
echo "sudo / privilege events — last ${HOURS}h"
echo "--------------------------------------------------------------------------------"
{
    journalctl --since "$SINCE" _COMM=sudo --no-pager -o short-iso 2>/dev/null || true
    journalctl --since "$SINCE" SYSLOG_IDENTIFIER=sudo --no-pager -o short-iso 2>/dev/null || true
} | awk '!seen[$0]++' | tail -n 40

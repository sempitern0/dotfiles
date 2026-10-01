#!/usr/bin/env bash
# Wait for a TCP endpoint without assuming netcat is installed.
set -u
set -o pipefail

usage() {
    cat <<'EOF_HELP'
Usage: monitorport <host> <port> [interval-seconds] [timeout-seconds]
Example: monitorport example.com 443 2 120

The final timeout is optional; 0 means wait indefinitely.
EOF_HELP
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
[[ $# -ge 2 ]] || { usage >&2; exit 2; }
HOST="$1" PORT="$2" INTERVAL="${3:-1}" LIMIT="${4:-0}"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || { printf 'Invalid port: %s\n' "$PORT" >&2; exit 2; }
[[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf 'Invalid interval.\n' >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { printf 'Invalid timeout.\n' >&2; exit 2; }

TTY=0
[[ -t 1 ]] && TTY=1
cleanup() { (( TTY == 1 )) && { tput cnorm 2>/dev/null || true; printf '\r\033[K'; }; }
trap cleanup EXIT INT TERM
(( TTY == 1 )) && tput civis 2>/dev/null || true

probe() {
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$HOST" "$PORT" >/dev/null 2>&1
    elif command -v timeout >/dev/null 2>&1; then
        timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$HOST" "$PORT" >/dev/null 2>&1
    else
        bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$HOST" "$PORT" >/dev/null 2>&1
    fi
}

start="$(date +%s)" count=0
printf 'Waiting for %s:%s ...\n' "$HOST" "$PORT"
while ! probe; do
    ((count+=1))
    now="$(date +%s)"
    if (( LIMIT > 0 && now - start >= LIMIT )); then
        printf '\nTimeout after %ss: %s:%s is still unavailable.\n' "$LIMIT" "$HOST" "$PORT" >&2
        exit 1
    fi
    if (( TTY == 1 )); then
        printf '\rAttempt %-5d elapsed=%ss' "$count" "$((now-start))"
    else
        printf 'Attempt %d: unavailable\n' "$count"
    fi
    sleep "$INTERVAL"
done
printf '\r\033[KReachable: %s:%s\n' "$HOST" "$PORT"

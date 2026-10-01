#!/usr/bin/env bash
# Inspect an endpoint certificate and report expiry state.
set -u
set -o pipefail

TARGET="${1:-}" PORT="${2:-443}"
[[ -n "$TARGET" ]] || { printf 'Usage: sslcheck <host> [port]\n' >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || { printf 'Invalid port.\n' >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { printf 'openssl is required.\n' >&2; exit 1; }

TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"' EXIT INT TERM
if command -v timeout >/dev/null 2>&1; then
    timeout 8 openssl s_client -connect "$TARGET:$PORT" -servername "$TARGET" </dev/null 2>/dev/null |
        openssl x509 -outform PEM >"$TMP" 2>/dev/null || true
else
    openssl s_client -connect "$TARGET:$PORT" -servername "$TARGET" </dev/null 2>/dev/null |
        openssl x509 -outform PEM >"$TMP" 2>/dev/null || true
fi
[[ -s "$TMP" ]] || { printf 'Unable to retrieve a certificate from %s:%s.\n' "$TARGET" "$PORT" >&2; exit 1; }

openssl x509 -in "$TMP" -noout -subject -issuer -serial -dates -ext subjectAltName 2>/dev/null
printf '\nExpiry checks:\n'
for days in 30 14 7 1; do
    if openssl x509 -in "$TMP" -noout -checkend "$((days*86400))" >/dev/null 2>&1; then
        printf '  valid for at least %2d day(s): yes\n' "$days"
    else
        printf '  valid for at least %2d day(s): NO\n' "$days"
    fi
done

#!/usr/bin/env bash
# HTTP endpoint status, redirect and security-header audit.
set -u
set -o pipefail

INPUT="${1:-}"
[[ -n "$INPUT" ]] || { printf 'Usage: httpcheck <domain-or-url>\n' >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 1; }
URL="$INPUT"
[[ "$URL" =~ ^https?:// ]] || URL="https://$URL"

TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"' EXIT INT TERM
METRICS="$(curl -sSIL --connect-timeout 5 --max-time 15 --compressed \
    -D "$TMP" -o /dev/null \
    -w '%{http_code}|%{time_total}|%{url_effective}' --proto =http,https --proto-redir =http,https --url "$URL")" || {
    rc=$?
    printf 'HTTP connection failed (curl rc=%s): %s\n' "$rc" "$URL" >&2
    exit "$rc"
}
[[ -n "$METRICS" ]] || { printf 'Connection failed: %s\n' "$URL" >&2; exit 1; }
IFS='|' read -r CODE TOTAL FINAL <<<"$METRICS"

printf 'HTTP AUDIT\n--------------------------------------------------------------------------------\n'
printf 'Requested : %s\nFinal     : %s\nStatus    : %s\nTime      : %ss\n' "$URL" "$FINAL" "$CODE" "$TOTAL"
printf '\nRedirect chain:\n'
grep -Ei '^(HTTP/|location:)' "$TMP" | sed 's/^/  /' || true

FINAL_HEADERS="$(awk '/^HTTP\// { block=""; next } { block=block $0 ORS } END { printf "%s", block }' "$TMP")"
printf '\nFinal response headers of interest:\n'
for h in server content-type strict-transport-security content-security-policy x-frame-options x-content-type-options referrer-policy permissions-policy; do
    value="$(grep -i "^${h}:" <<<"$FINAL_HEADERS" | tail -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' || true)"
    if [[ -n "$value" ]]; then printf '  %-28s %s\n' "$h" "$value"; else printf '  %-28s %s\n' "$h" '<missing/not-disclosed>'; fi
done

[[ "$CODE" =~ ^[23][0-9][0-9]$ ]] || exit 1

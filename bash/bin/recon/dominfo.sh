#!/usr/bin/env bash
# Quick DNS, TLS and WHOIS domain inventory.
set -u
set -o pipefail

usage() { printf 'Usage: dominfo <domain> [-o output-file]\n' >&2; }
[[ $# -ge 1 ]] || { usage; exit 2; }
DOMAIN="${1%.}"; shift
OUTPUT=""
while (($#)); do
    case "$1" in
        -o|--output) [[ $# -ge 2 ]] || { usage; exit 2; }; OUTPUT="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    shift
done
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ && "$DOMAIN" == *.* ]] || { printf 'Invalid domain name.\n' >&2; exit 2; }

report() {
    printf 'DOMAIN REPORT: %s\n' "$DOMAIN"
    printf '%0.s=' {1..80}; echo
    if command -v dig >/dev/null 2>&1; then
        local type
        for type in A AAAA MX NS TXT CAA; do
            printf '\n[%s]\n' "$type"
            dig +time=3 +tries=1 +short "$DOMAIN" "$type" 2>/dev/null | sed 's/^/  /' || true
        done
    else
        printf '\ndig unavailable; resolver addresses:\n'
        getent ahosts "$DOMAIN" 2>/dev/null | awk '!seen[$1]++ {print "  "$1}' || true
    fi

    printf '\n[TLS :443]\n'
    if command -v openssl >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 7 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null |
                openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null | sed 's/^/  /' || printf '  unavailable\n'
        else
            openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null |
                openssl x509 -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /' || printf '  unavailable\n'
        fi
    else
        printf '  openssl unavailable\n'
    fi

    printf '\n[WHOIS]\n'
    if command -v whois >/dev/null 2>&1; then
        whois "$DOMAIN" 2>/dev/null | grep -Ei '^(Registrar|Creation Date|Registry Expiry Date|Updated Date|Name Server|DNSSEC):' | head -n 30 | sed 's/^/  /' || true
    else
        printf '  whois unavailable\n'
    fi
}

if [[ -n "$OUTPUT" ]]; then
    report | tee "$OUTPUT"
else
    report
fi

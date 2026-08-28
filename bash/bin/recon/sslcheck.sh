#!/usr/bin/env bash
# OBJECTIVE: Inspect SSL/TLS certificate validity, expiration, and SANs.
set -euo pipefail

TARGET="${1:-}"
PORT="${2:-443}"

[[ -z "$TARGET" ]] && { echo "Usage: sslcheck <domain_or_ip> [port]"; exit 1; }

echo -e "\n[+] Checking SSL/TLS Certificate for ${TARGET}:${PORT}..."
echo "----------------------------------------------------------------------"

CERT_DATA=$(echo | openssl s_client -servername "$TARGET" -connect "${TARGET}:${PORT}" 2>/dev/null | openssl x509 -noout -dates -issuer -subject -ext subjectAltName 2>/dev/null)

if [[ -z "$CERT_DATA" ]]; then
    echo "[✘] Unable to establish SSL connection or retrieve certificate."
    exit 1
fi

echo "$CERT_DATA"
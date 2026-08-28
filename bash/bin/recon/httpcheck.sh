#!/usr/bin/env bash
set -euo pipefail

# Output color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOMAIN="${1:-}"
[[ -z "$DOMAIN" ]] && { echo "Usage: httpcheck <domain_or_url>"; exit 1; }

# Prepend HTTPS protocol if missing
[[ "$DOMAIN" != http* ]] && DOMAIN="https://$DOMAIN"

echo -e "\n${CYAN}[+] Analyzing HTTP status and headers for:${NC} ${DOMAIN}"
echo "--------------------------------------------------"

echo -e "${YELLOW}Redirect chain and response status:${NC}"
curl -sIL -A "Mozilla/5.0" "$DOMAIN" | grep -E "HTTP/|Location:|Server:|Strict-Transport-Security:" | sed 's/^/  /'
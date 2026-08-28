#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# SCRIPT: dominfo
# OBJECTIVE: Quick domain reconnaissance and DNS/WHOIS status verification.
#
# USAGE:
#   dominfo <domain_name>
#   Example: dominfo example.com
#
# EXTRACTED INFORMATION:
#   - Domain registration details (WHOIS data, registrar, expiration dates).
#   - DNS record resolution (A, AAAA, MX, NS records).
#   - IP address mapping and basic domain reachability.
# ==============================================================================

# Output color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Display usage instructions and exit
usage() {
    echo -e "${CYAN}Usage:${NC} dominfo <domain> [-o output_file]"
    echo "Example: dominfo example.com -o report.txt"
    exit 1
}

# Require at least one argument (the domain)
[[ $# -lt 1 ]] && usage

DOMAIN="$1"
OUTPUT_FILE=""
shift

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Perform domain reconnaissance and output results
fetch_domain_data() {
    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${CYAN} RECONNAISSANCE REPORT: ${DOMAIN}${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"

    echo -e "${GREEN}[1] Main DNS Records${NC}"
    echo "--------------------------------------------------"
    echo -e "${YELLOW}IPv4 (A):${NC}" && dig +short A "$DOMAIN" | sed 's/^/  /'
    echo -e "${YELLOW}IPv6 (AAAA):${NC}" && dig +short AAAA "$DOMAIN" | sed 's/^/  /'
    echo -e "${YELLOW}Name Servers (NS):${NC}" && dig +short NS "$DOMAIN" | sed 's/^/  /'
    echo -e "${YELLOW}Mail Servers (MX):${NC}" && dig +short MX "$DOMAIN" | sed 's/^/  /'
    echo -e "${YELLOW}TXT / SPF Records:${NC}" && dig +short TXT "$DOMAIN" | sed 's/^/  /'

    echo -e "\n${GREEN}[2] SSL/TLS Certificate Inspection${NC}"
    echo "--------------------------------------------------"
    if command -v openssl &>/dev/null; then
        echo | openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" 2>/dev/null | \
            openssl x509 -noout -dates -issuer -subject 2>/dev/null | sed 's/^/  /' || echo "  Unable to retrieve SSL certificate"
    else
        echo "  OpenSSL is not available"
    fi

    echo -e "\n${GREEN}[3] Registrar Information (WHOIS)${NC}"
    echo "--------------------------------------------------"
    if command -v whois &>/dev/null; then
        whois "$DOMAIN" 2>/dev/null | grep -Ei "Registrar:|Creation Date:|Registry Expiry Date:|Updated Date:|Registrant Organization:" | sed 's/^/  /' || echo "  WHOIS information restricted or unavailable"
    fi
}

# Save to output file if specified, otherwise display on stdout
if [[ -n "$OUTPUT_FILE" ]]; then
    fetch_domain_data | tee "$OUTPUT_FILE"
    echo -e "\n${GREEN}[✓] Results saved to:${NC} $OUTPUT_FILE"
else
    fetch_domain_data
fi
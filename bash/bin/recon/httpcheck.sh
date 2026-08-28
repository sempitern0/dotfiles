#!/usr/bin/env bash
set -euo pipefail

# Output color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CHROME_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
EDGE_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
FIREFOX_DESKTOP_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
ANDROID_MOBILE_AGENT="Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
IPHONE_MOBILE_AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1"
GOOGLE_BOT_DESKTOP_AGENT="Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"


DOMAIN_INPUT="${1:-}"
[[ -z "$DOMAIN_INPUT" ]] && { echo -e "${RED}Usage:${NC} httpcheck <domain_or_url>"; exit 1; }

# Extract hostname for DNS lookup
HOST=$(echo "$DOMAIN_INPUT" | sed -e 's|^[^/]*//||' -e 's|/.*||' -e 's|:.*||')

get_random_user_agent() {
    local agents=(
        "${CHROME_DESKTOP_AGENT}"
        "${EDGE_DESKTOP_AGENT}"
        "${FIREFOX_DESKTOP_AGENT}"
        "${ANDROID_MOBILE_AGENT}"
        "${IPHONE_MOBILE_AGENT}"
    )

    local rand_idx=$(( RANDOM % ${#agents[@]} ))
    echo "${agents[$rand_idx]}"
}


# Prepend HTTPS protocol if missing
if [[ "$DOMAIN_INPUT" != http* ]]; then
    URL="https://$HOST"
else
    URL="$DOMAIN_INPUT"
fi

echo -e "\n${CYAN}======================================================================${NC}"
echo -e "${CYAN} HTTP & DOMAIN AUDIT: ${HOST}${NC}"
echo -e "${CYAN}======================================================================${NC}\n"

# 1. Verification: DNS Resolution & Existence
echo -e "${GREEN}[1] DNS & Connectivity Verification${NC}"
echo "--------------------------------------------------"

IP=$(dig +short A "$HOST" | tail -n1 || true)

if [[ -z "$IP" ]]; then
    echo -e "  ${RED}[✘] Domain '$HOST' does not resolve or does not exist (No A Record).${NC}"
    echo -e "      Please check spelling or WHOIS registration status.\n"
    exit 1
else
    echo -e "  ${YELLOW}Resolved IP:${NC}     ${IP}"
    echo -e "  ${YELLOW}Target URL:${NC}      ${URL}"
fi

# 2. Performance and Redirect Chain
echo -e "\n${GREEN}[2] Latency & Redirect Chain${NC}"
echo "--------------------------------------------------"

USER_AGENT=$(get_random_user_agent)
echo -e "  ${BLUE}User-Agent selected:${NC} ${USER_AGENT:0:65}..."

CURL_OUT=$(curl -sIL \
    -A "$USER_AGENT" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Sec-Fetch-Dest: document" \
    -H "Sec-Fetch-Mode: navigate" \
    --compressed \
    -w "\n---METRICS---\n%{http_code}\n%{time_total}\n%{url_effective}" \
    "$URL" 2>/dev/null || true)

if [[ -z "$CURL_OUT" ]]; then
    echo -e "  ${RED}[✘] Connection failed (Timeout, connection refused, or SSL error).${NC}"
    exit 1
fi

HEADERS=$(echo "$CURL_OUT" | sed -n '1,/---METRICS---/p' | sed '$d')
METRICS=$(echo "$CURL_OUT" | sed -n '/---METRICS---/,$p' | tail -n +2)

FINAL_CODE=$(echo "$METRICS" | sed -n '1p')
TOTAL_TIME=$(echo "$METRICS" | sed -n '2p')
FINAL_URL=$(echo "$METRICS" | sed -n '3p')

echo -e "  ${YELLOW}Final Status Code:${NC} ${FINAL_CODE}"
echo -e "  ${YELLOW}Total Time:${NC}        ${TOTAL_TIME}s"
echo -e "  ${YELLOW}Final Destination:${NC} ${FINAL_URL}"

echo -e "\n  ${BLUE}Redirect Steps:${NC}"
echo "$HEADERS" | grep -E "^HTTP/|^Location:" | sed 's/^/    /'

# 3. Server & Technology Detection
echo -e "\n${GREEN}[3] Web Server & Technology${NC}"
echo "--------------------------------------------------"
SERVER=$(echo "$HEADERS" | grep -i "^Server:" | tail -n1 | cut -d':' -f2- | xargs || echo "Hidden/Not Disclosed")
POWERED=$(echo "$HEADERS" | grep -i "^X-Powered-By:" | tail -n1 | cut -d':' -f2- | xargs || echo "Not Disclosed")
CONTENT_TYPE=$(echo "$HEADERS" | grep -i "^Content-Type:" | tail -n1 | cut -d':' -f2- | xargs || echo "Unknown")

echo -e "  ${YELLOW}Server Header:${NC}   $SERVER"
echo -e "  ${YELLOW}X-Powered-By:${NC}    $POWERED"
echo -e "  ${YELLOW}Content-Type:${NC}    $CONTENT_TYPE"

# 4. Security Headers Audit
echo -e "\n${GREEN}[4] Security Headers Audit${NC}"
echo "--------------------------------------------------"


check_header() {
    local header_name="$1"
    local value
    value=$(echo "$HEADERS" | grep -i "^${header_name}:" | tail -n1 | cut -d':' -f2- | xargs || true)
    if [[ -n "$value" ]]; then
        echo -e "  ${GREEN}[✔] ${header_name}:${NC} $value"
    else
        echo -e "  ${RED}[✘] ${header_name}:${NC} Missing"
    fi
}

check_header "Strict-Transport-Security"
check_header "Content-Security-Policy"
check_header "X-Frame-Options"
check_header "X-Content-Type-Options"
check_header "Referrer-Policy"
check_header "Permissions-Policy"
echo ""
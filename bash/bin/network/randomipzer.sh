#!/usr/bin/env bash
# Generate random IP literals for test data, demos and parser validation.
# The default profile uses documentation ranges so generated values are not real targets.
set -u

MODE="doc4"
TIMES=1
DELIMITER=$'\n'

usage() {
    cat <<'EOF_HELP'
Usage: randomipzer [-t COUNT] [-m doc4|private4|doc6] [-d DELIMITER]

Modes:
  doc4      RFC 5737 documentation IPv4 ranges (default)
  private4  RFC 1918 private addresses
  doc6      2001:db8::/32 documentation IPv6 addresses

This utility is intended for test fixtures and examples, not target generation.
EOF_HELP
}

rand_octet() { printf '%d' "$((RANDOM % 256))"; }
rand_doc4() {
    case $((RANDOM % 3)) in
        0) printf '192.0.2.%d' "$((1 + RANDOM % 254))" ;;
        1) printf '198.51.100.%d' "$((1 + RANDOM % 254))" ;;
        *) printf '203.0.113.%d' "$((1 + RANDOM % 254))" ;;
    esac
}
rand_private4() {
    case $((RANDOM % 3)) in
        0) printf '10.%d.%d.%d' "$((RANDOM%256))" "$((RANDOM%256))" "$((1+RANDOM%254))" ;;
        1) printf '172.%d.%d.%d' "$((16+RANDOM%16))" "$((RANDOM%256))" "$((1+RANDOM%254))" ;;
        *) printf '192.168.%d.%d' "$((RANDOM%256))" "$((1+RANDOM%254))" ;;
    esac
}
rand_doc6() {
    printf '2001:db8:%x:%x:%x:%x:%x:%x' \
        "$((RANDOM%65536))" "$((RANDOM%65536))" "$((RANDOM%65536))" \
        "$((RANDOM%65536))" "$((RANDOM%65536))" "$((RANDOM%65536))"
}

while (($#)); do
    case "$1" in
        -t|--times) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TIMES="$2"; shift ;;
        --times=*) TIMES="${1#*=}" ;;
        -m|--mode) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; MODE="$2"; shift ;;
        --mode=*) MODE="${1#*=}" ;;
        -d|--delimiter) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; DELIMITER="$2"; shift ;;
        --delimiter=*) DELIMITER="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[[ "$TIMES" =~ ^[1-9][0-9]*$ ]] && (( TIMES <= 100000 )) || { printf 'COUNT must be between 1 and 100000.\n' >&2; exit 2; }
case "$MODE" in doc4|private4|doc6) ;; *) printf 'Invalid mode: %s\n' "$MODE" >&2; exit 2 ;; esac

declare -A seen=()
count=0
while (( count < TIMES )); do
    case "$MODE" in
        doc4) ip="$(rand_doc4)" ;;
        private4) ip="$(rand_private4)" ;;
        doc6) ip="$(rand_doc6)" ;;
    esac
    [[ -z "${seen[$ip]:-}" ]] || continue
    seen[$ip]=1
    (( count > 0 )) && printf '%b' "$DELIMITER"
    printf '%s' "$ip"
    ((count+=1))
done
printf '\n'

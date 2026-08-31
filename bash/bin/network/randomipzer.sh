#!/usr/bin/env bash

MODE="ipv4"
TIMES=0
DELIMITER=$'\n'

### --- ###
# Excluded IPv4 Addresses: Private networks (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16),
# Loopback (127.0.0.0/8), Link-Local (169.254.0.0/16), CGNAT (100.64.0.0/10), 
# Multicast/Reserved (224.0.0.0 through 255.255.255.255), and test/documentation blocks.
### --- ###

### --- ###
# Excluded IPv6 Addresses: Only IPs within the Global Unicast space (2000::/3) are generated, 
# explicitly excluding link-local (fe80::), unique local (fc00::), loopback (::1), and documentation (2001:db8::) 
### --- ###

show_help() {
    cat <<'EOF'
USAGE:
    randomipzer [OPTIONS]

OPTIONS:
    -m, --mode <ipv4|ipv6|both>  Select the type of IP to generate (default: ipv4)
    -t, --times <int>            Number of unique public IP addresses to generate (mandatory)
    -d, --delimiter <string>     Delimiter between generated IPs (default: \n)
    -h, --help                   Display help information

EXAMPLES:
    randomipzer --times 20
    randomipzer -t 100 -d '\n'
    randomipzer --times 50 --delimiter ' ' --mode ipv6
    nmap -p- --min-rate 5000 -sS 192.168.1.101 -D $(randomipzer -t 10 --delimiter ' ') --data-length 78 -vvv
EOF
}

# Check if an IPv4 address is globally routable (public)
is_public_ipv4() {
    local ip=$1
    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"

    # 0.0.0.0/8 (Current network)
    (( o1 == 0 )) && return 1

    # 10.0.0.0/8 (Private network)
    (( o1 == 10 )) && return 1

    # 100.64.0.0/10 (Carrier-grade NAT)
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 1

    # 127.0.0.0/8 (Loopback)
    (( o1 == 127 )) && return 1

    # 169.254.0.0/16 (Link-local)
    (( o1 == 169 && o2 == 254 )) && return 1

    # 172.16.0.0/12 (Private network)
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 1

    # 192.0.0.0/24 & 192.0.2.0/24 (IETF assignment / TEST-NET-1)
    (( o1 == 192 && o2 == 0 && (o3 == 0 || o3 == 2) )) && return 1

    # 192.88.99.0/24 (6to4 Relay)
    (( o1 == 192 && o2 == 88 && o3 == 99 )) && return 1

    # 192.168.0.0/16 (Private network)
    (( o1 == 192 && o2 == 168 )) && return 1

    # 198.18.0.0/15 (Benchmarking)
    (( o1 == 198 && (o2 == 18 || o2 == 19) )) && return 1

    # 198.51.100.0/24 (TEST-NET-2)
    (( o1 == 198 && o2 == 51 && o3 == 100 )) && return 1

    # 203.0.113.0/24 (TEST-NET-3)
    (( o1 == 203 && o2 == 0 && o3 == 113 )) && return 1

    # 224.0.0.0/4 & 240.0.0.0/4 (Multicast, Reserved, Broadcast)
    (( o1 >= 224 )) && return 1

    return 0
}

# Check if an IPv6 address is globally routable (public)
is_public_ipv6() {
    local ip=$1
    local b1="${ip%%:*}"
    local b1_val=$((16#$b1))

    # Global Unicast Address range (2000::/3 -> 0x2000 to 0x3FFF)
    (( b1_val < 0x2000 || b1_val > 0x3fff )) && return 1

    # Exclude 2001:db8::/32 (Documentation)
    if [[ "$ip" =~ ^2001:0*db8: ]]; then
        return 1
    fi

    return 0
}

rand_ipv4() {
    printf "%d.%d.%d.%d" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

rand_ipv6() {
    # Generate within 2000::/3 space (0x2000 to 0x3FFF)
    local b1
    b1=$(printf "%04x" $((0x2000 + RANDOM % 0x2000)))
    printf "%s:%04x:%04x:%04x:%04x:%04x:%04x:%04x" \
        "$b1" $((RANDOM % 65536)) $((RANDOM % 65536)) $((RANDOM % 65536)) \
        $((RANDOM % 65536)) $((RANDOM % 65536)) $((RANDOM % 65536)) $((RANDOM % 65536))
}

generate_ips() {
    local target_count=$1
    local mode=$2
    local delim=$3

    declare -A seen
    local generated=0

    while (( generated < target_count )); do
        local ip=""
        case "$mode" in
            ipv4)
                while true; do
                    ip=$(rand_ipv4)
                    is_public_ipv4 "$ip" && break
                done
                ;;
            ipv6)
                while true; do
                    ip=$(rand_ipv6)
                    is_public_ipv6 "$ip" && break
                done
                ;;
            both)
                while true; do
                    if (( RANDOM % 2 == 0 )); then
                        ip=$(rand_ipv4)
                        is_public_ipv4 "$ip" && break
                    else
                        ip=$(rand_ipv6)
                        is_public_ipv6 "$ip" && break
                    fi
                done
                ;;
        esac

        # Prevent duplicates to guarantee exact requested count
        if [[ -z "${seen[$ip]:-}" ]]; then
            seen[$ip]=1
            if (( generated > 0 )); then
                printf "%b" "$delim"
            fi
            printf "%s" "$ip"
            (( generated++ ))
        fi
    done
    printf "\n"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--times)
            TIMES="${2:-}"
            shift 2
            ;;
        --times=*)
            TIMES="${1#*=}"
            shift
            ;;
        -m|--mode)
            MODE="${2:-}"
            shift 2
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        -d|--delimiter)
            DELIMITER="${2:-}"
            shift 2
            ;;
        --delimiter=*)
            DELIMITER="${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
    esac
done

MODE="${MODE,,}"

if [[ -z "$TIMES" || ! "$TIMES" =~ ^[0-9]+$ || "$TIMES" -le 0 ]]; then
    echo "Error: The option -t/--times must be an integer greater than 0." >&2
    exit 1
fi

if [[ "$MODE" != "ipv4" && "$MODE" != "ipv6" && "$MODE" != "both" ]]; then
    echo "Warning: Invalid mode '$MODE'. Falling back to 'ipv4'." >&2
    MODE="ipv4"
fi

generate_ips "$TIMES" "$MODE" "$DELIMITER"
#!/usr/bin/env bash
# OpenVPN --down kill-switch helper.
# It disconnects only interfaces carrying a default route; it does not kill
# DHCP processes or stop the whole networking service.
set -u
set -o pipefail

if (( EUID != 0 )); then
    printf 'openvpndown must run as root (normally OpenVPN invokes it).\n' >&2
    exit 1
fi

if [[ "${script_type:-}" != "down" && "${OPENVPN_KILLSWITCH_CONFIRM:-}" != "YES" ]]; then
    cat >&2 <<'EOF_WARN'
Refusing direct execution.
This command intentionally disconnects default-route interfaces.
OpenVPN invokes it with script_type=down. For a manual test, explicitly run:
  sudo OPENVPN_KILLSWITCH_CONFIRM=YES openvpndown
EOF_WARN
    exit 2
fi

command -v ip >/dev/null 2>&1 || { printf 'iproute2 is required.\n' >&2; exit 1; }
VPN_DEV="${dev:-}"
declare -A seen=()
interfaces=()
while read -r iface; do
    [[ -n "$iface" && "$iface" != lo && "$iface" != "$VPN_DEV" ]] || continue
    [[ "$iface" == tun* || "$iface" == tap* || "$iface" == wg* ]] && continue
    [[ -z "${seen[$iface]:-}" ]] || continue
    seen[$iface]=1
    interfaces+=("$iface")
done < <({ ip -4 route show default 2>/dev/null; ip -6 route show default 2>/dev/null; } | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1)}}')

((${#interfaces[@]})) || { printf 'No non-VPN default-route interface found.\n' >&2; exit 0; }
printf 'VPN down: disconnecting default-route interface(s): %s\n' "${interfaces[*]}" >&2
logger -t openvpndown "VPN down kill-switch: disconnecting ${interfaces[*]}" 2>/dev/null || true

for iface in "${interfaces[@]}"; do
    if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
        nmcli device disconnect "$iface" >/dev/null 2>&1 || ip link set dev "$iface" down || true
    else
        ip link set dev "$iface" down || true
    fi
done

printf 'Recovery: reconnect the network from your desktop UI, or use nmcli device connect <iface>.\n' >&2

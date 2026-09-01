#!/usr/bin/env bash

###
# This one cut the network connection when the vpn is down. 
# I assign this script when I run openvpn to avoid leak my real network information 
# in the middle of a process.
###

### Example
# openvpn --script-security 2 --down "$HOME/scripts/openvpndown.sh" --config <openvpn file>
###

echo "[-] Disabling network interfaces..."
systemctl stop network-manager
killall -9 dhclient

for network_interface in $(ifconfig | grep -iEo '^[a-z0-9]+:' | grep -v '^lo:$' | cut -d ':' -f 1) 
do
	ifconfig "$network_interface" 0.0.0.0 down
done
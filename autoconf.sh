#!/bin/vbash

function get_next_if() {
        excluded_interfaces=("$@")
        lowest_ifindex=-1
        lowest_ifname=""
        for interface_path in /sys/class/net/*; do
                found=false
                interface=$(basename "$interface_path")
                for excluded_interface in "${excluded_interfaces[@]}"; do
                        if [ "$excluded_interface" == "$interface" ]; then
                                found=true
                                break
                        fi
                done
                if [ "$found" == true ]; then
                        continue
                fi
                ifindex=$(udevadm info -q property "$interface_path" | grep -E '^IFINDEX=' | cut -d'=' -f2)
                if [[ "$ifindex" =~ ^[0-9]+$ ]]; then
                        if [ "$lowest_ifindex" -eq -1 ] || [ "$ifindex" -lt "$lowest_ifindex" ]; then
                          lowest_ifindex="$ifindex"
                          lowest_ifname="$interface"
                        fi
                fi
        done
        if [ "$lowest_ifindex" -eq -1 ]; then
                echo ""
        else
                echo "$lowest_ifname"
        fi
}

echo "Determining Interfaces"

# workaround for udevd, not ideal but workable. 
WAN_INT=$(get_next_if "lo")
LAN_INT=$(get_next_if "lo" "${WAN_INT}")

if [[ -n "$WAN_INT" && -n "$LAN_INT" && "$WAN_INT" != "$LAN_INT" ]]; then
    echo "Interfaces are good: WAN:${WAN_INT}, LAN:${LAN_INT}"
else
    echo "Conditions not met. Interfaces not correct. WAN:${WAN_INT}, LAN:${LAN_INT}"
    exit 1
fi

echo "Beginning Configuration of Router NAT rules"
export IPV4_ADDR=$(ip -4 addr show dev $WAN_INT | grep -oP 'inet\s+\K[^\s]+'|sed "s/\([0-9]\+\.[0-9]\+\.[0-9]\+\.\)\([0-9]\+\)\/\([0-9]\+\)/\10\/\3/")
export TEAM_ROUTER=$(echo "${IPV4_ADDR}" | awk -F'.' '{print $3}')
export CURRENT_LAN_ADDR=$(ip -4 addr show dev $LAN_INT | grep -oP 'inet\s+\K[^\s]+')

export FINAL_LAN_ADDR="192.168.220.2/24"
export FINAL_LAN_SUBNET=$(echo "${FINAL_LAN_ADDR}"|sed "s/\([0-9]\+\.[0-9]\+\.[0-9]\+\.\)\([0-9]\+\)\/\([0-9]\+\)/\10\/\3/")
export TEMP_CONF=$(mktemp)

if [ -f "/configured.runonce" -o -f "/boot/configured.runonce" ]; then
	echo "Configuration already set. "
	exit 0
fi

if [ -z "$IPV4_ADDR" ]; then
        echo "Error: Could not configure IPv4 Address Automatically"
        exit 1
fi

if [ -n "${CURRENT_LAN_ADDR}" ] && [ "${CURRENT_LAN_ADDR}" = "${FINAL_LAN_ADDR}" ]; then
	echo "Configuration already appears set. Stopping"
	exit 1
fi

echo "Got IPv4 Address: ${IPV4_ADDR}, will be storing configuration in ${TEMP_CONF}"


cat <<EOF >$TEMP_CONF
source /opt/vyatta/etc/functions/script-template
configure
echo "deleting base configurations"
delete system login banner
delete nat
delete interfaces ethernet $LAN_INT
delete service lldp
delete service ntp
delete service dns forwarding
commit
echo "configuring interface $LAN_INT"
set interfaces ethernet $LAN_INT address '192.168.220.2/24'
commit
echo "setting nat rules"
set nat destination rule 10 destination address '$FINAL_LAN_SUBNET'
set nat destination rule 10 inbound-interface '$LAN_INT'
set nat destination rule 10 translation address '$IPV4_ADDR'
set nat destination rule 20 destination address '$IPV4_ADDR'
set nat destination rule 20 inbound-interface '$WAN_INT'
set nat destination rule 20 translation address '$FINAL_LAN_SUBNET'
set nat source rule 10 outbound-interface '$WAN_INT'
set nat source rule 10 source address '$IPV4_ADDR'
set nat source rule 10 translation address '$FINAL_LAN_SUBNET'
set nat source rule 20 outbound-interface '$LAN_INT'
set nat source rule 20 source address '$FINAL_LAN_SUBNET'
set nat source rule 20 translation address '$IPV4_ADDR'
set nat source rule 30 outbound-interface '$WAN_INT'
set nat source rule 30 translation address 'masquerade'
commit
echo "setting services"
set system host-name 'team-router$TEAM_ROUTER'
set system time-zone America/Los_Angeles
set firewall all-ping enable
set service lldp interface all
set service lldp legacy-protocols cdp
set service dns forwarding allow-from 0.0.0.0/0
set service dns forwarding listen-address 0.0.0.0
set system ntp listen-address 0.0.0.0
echo "setting authentication"
echo "removing http service after deployment"
delete service https
commit
save
EOF
chmod +x "${TEMP_CONF}"
$TEMP_CONF
#touch /configured.runonce
#touch /boot/configured.runonce


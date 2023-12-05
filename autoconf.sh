#!/bin/vbash
echo "Beginning Configuration of Router NAT rules"
export IPV4_ADDR=$(ip -4 addr show dev eth0 | grep -oP 'inet\s+\K[^\s]+'|sed "s/\([0-9]\+\.[0-9]\+\.[0-9]\+\.\)\([0-9]\+\)\/\([0-9]\+\)/\10\/\3/")
export CURRENT_LAN_ADDR=$(ip -4 addr show dev eth1 | grep -oP 'inet\s+\K[^\s]+')

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
delete interfaces ethernet eth1
delete service lldp
delete service ntp
delete service dns forwarding
commit
echo "configuring interface eth1"
set interfaces ethernet eth1 address '192.168.220.2/24'
commit
echo "setting nat rules"
set nat destination rule 10 destination address '$FINAL_LAN_SUBNET'
set nat destination rule 10 inbound-interface 'eth1'
set nat destination rule 10 translation address '$IPV4_ADDR'
set nat destination rule 20 destination address '$IPV4_ADDR'
set nat destination rule 20 inbound-interface 'eth0'
set nat destination rule 20 translation address '$FINAL_LAN_SUBNET'
set nat source rule 10 outbound-interface 'eth0'
set nat source rule 10 source address '$IPV4_ADDR'
set nat source rule 10 translation address '$FINAL_LAN_SUBNET'
set nat source rule 20 outbound-interface 'eth1'
set nat source rule 20 source address '$FINAL_LAN_SUBNET'
set nat source rule 20 translation address '$IPV4_ADDR'
set nat source rule 30 outbound-interface 'eth0'
set nat source rule 30 translation address 'masquerade'
commit
echo "setting services"
set system time-zone America/Los_Angeles
set system host-name 'amnesiac'
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


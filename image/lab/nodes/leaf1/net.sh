ip addr add 10.255.1.1/32 dev lo
iface eth1 9000 10.0.1.1/31   # -> spine1
iface eth2 9000 10.0.2.1/31   # -> spine2

# The "switch" half of the leaf: VLAN 10, access ports eth3=lb1 eth4=web1 eth5=web2,
# SVI vlan10 = default gateway of the rack. (see access_vlan in roles/common.sh)
access_vlan 10 10.10.10.1/24 eth3 eth4 eth5

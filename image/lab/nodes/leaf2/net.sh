ip addr add 10.255.1.2/32 dev lo
iface eth1 9000 10.0.1.3/31   # -> spine1
iface eth2 9000 10.0.2.3/31   # -> spine2

access_vlan 20 10.10.20.1/24 eth3   # db1   (data)
access_vlan 30 10.10.30.1/24 eth4   # dns1  (services)

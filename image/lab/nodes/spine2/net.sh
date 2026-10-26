ip addr add 10.255.0.2/32 dev lo
iface eth1 9000 10.0.2.0/31   # -> leaf1
iface eth2 9000 10.0.2.2/31   # -> leaf2
iface eth3 9000 10.0.2.4/31   # -> border

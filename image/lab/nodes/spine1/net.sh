ip addr add 10.255.0.1/32 dev lo
iface eth1 9000 10.0.1.0/31   # -> leaf1
iface eth2 9000 10.0.1.2/31   # -> leaf2
iface eth3 9000 10.0.1.4/31   # -> border

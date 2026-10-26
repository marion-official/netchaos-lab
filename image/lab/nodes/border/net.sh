ip addr add 10.255.1.3/32 dev lo
iface eth1 9000 10.0.1.5/31   # -> spine1
iface eth2 9000 10.0.2.5/31   # -> spine2
iface eth3 1500 10.0.9.0/31   # -> fw

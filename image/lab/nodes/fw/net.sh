iface eth1 1500 10.0.9.1/31       # inside  -> border
iface eth2 1500 203.0.113.1/24    # outside -> internet
ip addr add 203.0.113.10/32 dev eth2   # public VIP for the shop (DNAT to lb1)
ip route add 10.0.0.0/8 via 10.0.9.0   # everything internal lives behind border

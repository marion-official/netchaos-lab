# Fabric routers (spines, leaves, border): Linux + FRR, eBGP.
sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv4.fib_multipath_hash_policy=1   # ECMP hashes on L4 (per flow), like real switches
sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
cp "/lab/nodes/$(hostname)/frr.conf" /etc/frr/frr.conf
chown frr:frr /etc/frr/frr.conf
echo frr > /etc/lab-services
svc start frr

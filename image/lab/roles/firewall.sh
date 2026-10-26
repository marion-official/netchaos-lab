# Edge firewall: stateful filtering + DNAT for the public VIP + SNAT for outbound.
sysctl -qw net.ipv4.ip_forward=1
cp /lab/nodes/fw/nftables.nft /etc/nftables.conf
nft -f /etc/nftables.conf
: > /etc/lab-services

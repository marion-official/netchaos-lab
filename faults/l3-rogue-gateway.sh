# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L2/L3 duplicate gateway IP"
fault_pick() { P_T=$(pick web1 web2); }
fault_ticket() {
  say "Errors on shop.example.com come and go: some minutes fine, some minutes HTTP 5xx or timeouts."
  say "HAProxy marks $P_T DOWN constantly, other backends occasionally."
  say "Someone was 'testing keepalived' on a web server earlier today."
}
fault_inject() {
  x $P_T "ip addr add 10.10.10.1/24 dev eth1 && arping -q -U -c 3 -I eth1 10.10.10.1"
  x lb1  "ip neigh flush dev eth1"
}
fault_verify() { x $P_T "! ip -4 addr show dev eth1 | grep -q ' 10.10.10.1/'"; }
fault_fix() {
  x $P_T "ip addr del 10.10.10.1/24 dev eth1; ip route replace default via 10.10.10.1"
  x leaf1 "for d in vlan10 br0; do [ -e /sys/class/net/\$d ] && ip -4 addr show dev \$d | grep -q 10.10.10.1 && arping -q -U -c 3 -I \$d 10.10.10.1; done; true"
  for n in lb1 web1 web2; do x $n "ip neigh flush dev eth1"; done
}
fault_hints() {
  echo "From a server in VLAN 10: who answers for the default gateway? 'ip neigh show 10.10.10.1' a few times, and compare with leaf1's real MAC (ip link show on the SVI)."
  echo "arping -I eth1 -c 5 10.10.10.1 from lb1. Count the different MAC addresses in the replies."
  echo "Find the owner of the unexpected MAC (ip -br link on each server), then look at its addresses with ip -br addr and its routing table."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_T has 10.10.10.1/24 configured on eth1 - the IP of VLAN 10's default gateway (the SVI on
leaf1). Every host in the VLAN that ARPs for its gateway may get $P_T's MAC instead of leaf1's, and
then sends all off-subnet traffic to $P_T, which is not a router and drops it. $P_T itself is broken
all the time: the gateway address is now local to it, so its default route points at itself.

How to see it:
  lb1/web:  arping -I eth1 -c 5 10.10.10.1  -> replies from TWO MACs
            ip neigh show 10.10.10.1        -> MAC is $P_T's, not leaf1's
  $P_T:     ip -br addr                     -> 10.10.10.1/24 as a secondary on eth1
            ip route get 10.10.20.10        -> "local"/broken path instead of via the leaf
Fix:
  $P_T:     ip addr del 10.10.10.1/24 dev eth1 ; check its default route (ip route)
  leaf1:    arping -U -I <svi> 10.10.10.1   (gratuitous ARP to win the address back)
  hosts:    ip neigh flush dev eth1          (or wait for the poisoned entries to expire)
Lesson: a rogue device answering for the gateway is the most damaging duplicate IP there is. Real
networks defend with DHCP snooping + dynamic ARP inspection; keepalived/VRRP tests belong on
dedicated VIPs, never on the gateway address.
EOT
}

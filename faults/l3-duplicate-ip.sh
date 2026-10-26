# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L2 duplicate IP / ARP"
fault_pick()   { P_T=$(pick web1 web2); }
fault_ticket() {
  say "Since about 10 minutes ago, shop.example.com fails for customers: 'connection refused', or it works on retry."
  say "HAProxy on lb1 shows both backends UP and lb1's logs look normal - some requests never even reach it."
  say "An engineer was 'testing a failover VIP' on one of the web servers."
}
fault_inject() {
  x $P_T "ip addr add 10.10.10.10/24 dev eth1 && sysctl -qw net.ipv4.conf.eth1.arp_announce=0 && arping -q -U -c 3 -I eth1 10.10.10.10"
  x leaf1 "ip neigh flush dev vlan10 2>/dev/null; ip neigh flush all 2>/dev/null; true"
  x $P_T "arping -q -U -c 2 -I eth1 10.10.10.10"
}
fault_verify() { x $P_T "! ip -4 addr show dev eth1 | grep -q '10.10.10.10/'"; }
fault_fix() {
  x $P_T "ip addr del 10.10.10.10/24 dev eth1"
  x leaf1 "ip neigh flush all"
  x lb1 "arping -q -U -c 2 -I eth1 10.10.10.10"
}
fault_hints() {
  echo "Connection refused = something answered with a TCP RST. Who? tcpdump on the fw inside interface (eth1) and look at MAC addresses: tcpdump -eni eth1 host 10.10.10.10"
  echo "Compare the MAC that answers for 10.10.10.10 with lb1's real MAC (ip link show eth1 on lb1). On leaf1: ip neigh show 10.10.10.10. On the same VLAN: arping -I eth1 10.10.10.10 from web1 - how many different MACs reply?"
  echo "Find which box owns the second MAC: ip -br link / ip -br addr on the servers in VLAN 10."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_T has lb1's IP 10.10.10.10 configured as a secondary address (a leftover "test VIP").
Both hosts answer ARP for 10.10.10.10; leaf1's ARP cache flips between the two MACs. When it points
to $P_T, customer SYNs to port 80 land on $P_T, where nginx doesn't listen on that IP -> RST ->
"connection refused". lb1 never sees those requests, so its logs look clean.

How to see it:
  VLAN 10:  arping -I eth1 -c 4 10.10.10.10 (from web1/web2/lb1) -> replies from TWO MACs
  leaf1:    ip neigh show 10.10.10.10 -> MAC changes over time / doesn't match lb1's eth1
  fw:       tcpdump -eni eth1 'tcp[tcpflags] & tcp-rst != 0' -> RSTs from 10.10.10.10 with the wrong MAC
  $P_T:     ip -br addr -> 10.10.10.10/24 on eth1
Fix:
  $P_T:     ip addr del 10.10.10.10/24 dev eth1
  leaf1:    ip neigh flush all   (or wait for the entry to age out)
  lb1:      arping -U -I eth1 10.10.10.10  (gratuitous ARP to re-claim the address quickly)
Lesson: intermittent + "works on retry" + source never sees the traffic -> think ARP/duplicate IP.
EOT
}

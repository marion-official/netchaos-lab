# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 IPv4 header (TTL)"
fault_pick() { P_TTL=$(pick 3 4); }
fault_ticket() {
  say "shop.example.com times out for ALL customers on the internet."
  say "From inside the DC (e.g. curl http://10.10.10.10/ on web1) the shop works perfectly."
  say "A 'kernel tuning' sysctl profile was rolled out to some servers this morning."
}
fault_inject() { x lb1 "sysctl -qw net.ipv4.ip_default_ttl=$P_TTL"; }
fault_verify() { x lb1 "[ \$(sysctl -n net.ipv4.ip_default_ttl) -ge 32 ]"; }
fault_fix()    { x lb1 "sysctl -qw net.ipv4.ip_default_ttl=64"; }
fault_hints() {
  echo "Follow ONE customer connection: tcpdump on fw (both interfaces), then on lb1. Which packets make it, in which direction?"
  echo "lb1 answers the SYN, but the SYN-ACK never reaches fw. Capture on lb1 with 'tcpdump -vni eth1' and read every IP header field of what lb1 sends, and of anything that comes back."
  echo "ICMP 'time exceeded in-transit' is the network telling you something about a field in the IP header. Which device sent it, and why? (sysctl -a | grep ttl)"
}
fault_solution() { cat <<EOT
ROOT CAUSE: lb1's default IPv4 TTL was set to $P_TTL (net.ipv4.ip_default_ttl). Every router decrements
the TTL and discards the packet at 0. lb1 -> leaf1 -> spine -> border -> fw -> customer is more hops
than $P_TTL, so lb1's replies die inside the fabric and the router sends "ICMP time exceeded" back.
Inside the DC (same VLAN, zero router hops) everything works.

How to see it:
  lb1:   tcpdump -vni eth1 host 203.0.113.100  -> SYN in, SYN-ACK out with "ttl $P_TTL"
         tcpdump -ni eth1 icmp                 -> "time exceeded in-transit" from a fabric router
  fw:    tcpdump -ni eth1                      -> the SYN-ACK never arrives
         traceroute -n 203.0.113.100 from lb1  -> works (traceroute sets its own TTLs!) - a trap
Fix:
  lb1:   sysctl -w net.ipv4.ip_default_ttl=64
Lesson: one-way traffic = look at what's different in the return packets. TTL also tells you how far
away a sender is (64/128/255 minus hops) - handy for spotting spoofing and asymmetric paths.
EOT
}

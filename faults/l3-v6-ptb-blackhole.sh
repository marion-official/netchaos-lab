# SPOILER: fault definition. Needs dual-stack mode (./labctl up --ipv6).
FAULT_LEVEL=3
FAULT_LAYER="L3 IPv6 path MTU (packet too big)"
fault_supported() { ipv6_on; }
fault_pick() { P_MTU=$(pick 1400 1420 1380); }
fault_ticket() {
  say "Over IPv6, customers can load the shop homepage but downloading /report hangs forever."
  say "Over IPv4 everything works, /report included - so 'it can't be the network'."
  say "The border team applied an 'ICMPv6 hardening' template and some link changes last week."
}
fault_inject() {
  x border "ip link set eth3 mtu $P_MTU && nft -f - <<'NFT'
table inet hardening6 {
  chain out {
    type filter hook output priority filter; policy accept;
    icmpv6 type packet-too-big counter drop comment \"no ICMPv6 noise\"
  }
}
NFT"
  x fw "ip link set eth1 mtu $P_MTU"
}
fault_verify() { x inet-client "for i in 1 2 3; do s=\$(curl -6 -s -o /dev/null -m 6 -w '%{size_download}' http://shop.example.com/report); [ \"\$s\" -gt 1000000 ] || exit 1; done"; }
fault_fix() {
  x border "nft delete table inet hardening6 2>/dev/null; ip link set eth3 mtu 1500"
  x fw "ip link set eth1 mtu 1500"
  x lb1 "ip -6 route flush cache"
}
fault_hints() {
  echo "Small works, big hangs - but only over IPv6. Watch a failing download on lb1: tcpdump -ni eth1 'ip6 and tcp port 80'. Packet sizes? Retransmissions?"
  echo "Test the IPv6 path MTU from lb1: tracepath -6 2001:db8:113::100, and ping -6 -M do -s 1452 2001:db8:113::100 (then smaller). Compare with the IPv4 equivalents."
  echo "In IPv6, routers NEVER fragment. A router that can't forward a big packet must tell the sender (ICMPv6 type 2). Which router should send it, and does it? (nft list ruleset on the routers)"
}
fault_solution() { cat <<EOT
ROOT CAUSE: the border<->fw link has MTU $P_MTU, and border drops its own outgoing ICMPv6
"Packet Too Big" messages (table 'hardening6'). IPv6 routers never fragment: PTB is the ONLY way lb1
can learn to send smaller packets. Dropped PTB = big IPv6 packets silently vanish (black hole).
IPv4 works because border still sends ICMPv4 "fragmentation needed", so IPv4 PMTUD succeeds - which
is exactly why "IPv4 works, so it's not the network" was wrong.

How to see it:
  lb1:     tcpdump -ni eth1 'ip6 and tcp port 80' -> 1440-byte segments retransmitted, never ACKed
           ping -6 -M do -s 1452 2001:db8:113::100  -> silence ; -s 1300 -> works
  border:  ip link show eth3                         -> mtu $P_MTU
           nft list ruleset                          -> 'icmpv6 type packet-too-big drop' counter rising
Fix:
  border:  nft delete table inet hardening6   (never block ICMPv6 type 2)
           and/or restore MTU 1500 on border:eth3 and fw:eth1
Lesson: IPv6 moved fragmentation to the sender; PTB filtering is a classic IPv6-only outage.
Minimum IPv6 MTU is 1280 - anything bigger relies on PMTUD working end to end.
EOT
}

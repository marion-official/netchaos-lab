# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L3 MTU / PMTUD"
fault_pick()   { P_MTU=$(pick 1400 1380 1420); }
fault_ticket() {
  say "Customers report that the shop HOMEPAGE works fine, but downloading /report hangs forever."
  say "Inside the DC, downloading /report from lb1 works."
  say "Yesterday the security team 'hardened' the border router, and the network team prepared the firewall link for a future IPsec tunnel."
}
fault_inject() {
  x border "ip link set eth3 mtu $P_MTU && nft -f - <<'NFT'
table ip hardening {
  chain out {
    type filter hook output priority filter; policy accept;
    icmp type destination-unreachable counter drop comment \"don't leak ICMP\"
  }
}
NFT"
  x fw "ip link set eth1 mtu $P_MTU"
}
fault_verify() { x inet-client "for i in 1 2 3; do s=\$(curl -s -o /dev/null -m 6 -w '%{size_download}' http://shop.example.com/report); [ \"\$s\" -gt 1000000 ] || exit 1; done"; }
fault_fix() {
  x border "nft delete table ip hardening 2>/dev/null; ip link set eth3 mtu 1500; ip route flush cache"
  x fw "ip link set eth1 mtu 1500"
  x lb1 "ip route flush cache"
}
fault_hints() {
  echo "Small responses work, big ones hang. Watch a failing download with tcpdump on lb1 (tcpdump -ni eth1 host 203.0.113.100): how big are the packets lb1 sends? Are they retransmitted?"
  echo "Test the path MTU yourself from lb1 towards the internet: ping -M do -s 1472 203.0.113.100, then smaller sizes. Also 'tracepath 203.0.113.100'."
  echo "Every hop's MTU: ip -br link / ip link show on each box on the path (leaf1, spines, border, fw). And when a router can't forward a big DF packet it must send ICMP 'frag needed' - is anything eating ICMP? (nft list ruleset)"
}
fault_solution() { cat <<EOT
ROOT CAUSE: the border<->fw link was set to MTU $P_MTU, AND the border router drops all outgoing ICMP
destination-unreachable (nft table 'hardening'). lb1 sends full 1500-byte packets with DF set; border
can't forward them and SHOULD reply "fragmentation needed, MTU $P_MTU" so lb1 lowers its packet size
(Path MTU Discovery). That ICMP is dropped, so the big packets vanish silently: a PMTUD black hole.
Small responses fit in one small packet, so the homepage works.

How to see it:
  lb1:     tcpdump -ni eth1 host 203.0.113.100 -> length 1448 segments retransmitted, never ACKed
           ping -M do -s 1472 203.0.113.100     -> silence ; -s 1300 works
  border:  ip -br link / ip link show eth3      -> mtu $P_MTU
           nft list ruleset                     -> the drop counter increasing
Fix (any of these, best first):
  1. put the MTU back to 1500 on border:eth3 and fw:eth1 (if nothing needs it smaller)
  2. stop dropping ICMP type 3 code 4 (frag-needed): never block it blindly
  3. MSS clamping on the router: nft ... tcp flags syn tcp option maxseg size set rt mtu
Lesson: "small works, big hangs" = MTU until proven otherwise. ICMP is not optional.
EOT
}

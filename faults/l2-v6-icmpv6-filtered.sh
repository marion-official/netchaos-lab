# SPOILER: fault definition. Needs dual-stack mode (./labctl up --ipv6).
FAULT_LEVEL=2
FAULT_LAYER="L2/L3 IPv6 neighbour discovery (ICMPv6)"
fault_supported() { ipv6_on; }
fault_pick() { :; }
fault_ticket() {
  say "IPv6 customers can't reach shop.example.com at all (timeouts). IPv4 customers are fine."
  say "The security team rolled out an 'ICMP hardening' policy to the network security devices:"
  say "'we only blocked ping-like stuff, nothing important'."
}
fault_inject() {
  x fw "sed -i '/ipv6-icmp accept comment \"NDP, PMTUD\"/d' /etc/nftables.conf && nft -f /etc/nftables.conf && ip -6 neigh flush dev eth1"
  x border "ip -6 neigh flush dev eth3"
}
fault_verify() { x fw "nft list chain inet filter input | grep -Eq 'ipv6-icmp|icmpv6'"; }
fault_fix() {
  x fw "python3 - <<'PY'
p = '/etc/nftables.conf'; s = open(p).read()
if 'NDP, PMTUD' not in s:
    s = s.replace('    meta l4proto icmp accept\n', '    meta l4proto icmp accept\n    meta l4proto ipv6-icmp accept comment \"NDP, PMTUD\"\n', 1)
    open(p, 'w').write(s)
PY
nft -f /etc/nftables.conf"
}
fault_hints() {
  echo "Find where IPv6 stops: from border, 'ping -6 fd00:0:9::2' (the fw's inside address). Does IPv4 to the same box (ping 10.0.9.1) work?"
  echo "Check the neighbour table on both ends of that link: 'ip -6 neigh' on border and on fw. IPv6 has no ARP - what replaced it, and what protocol does it run over?"
  echo "tcpdump -ni eth1 icmp6 on fw while border pings it. Neighbour Solicitations arrive... then what? Read fw's ruleset (nft list ruleset) with IPv6 in mind."
}
fault_solution() { cat <<EOT
ROOT CAUSE: the fw's input chain no longer accepts ICMPv6 ("meta l4proto ipv6-icmp accept" was removed).
IPv6 resolves neighbours with ICMPv6 Neighbor Solicitation/Advertisement (NDP), not ARP. With the fw
dropping incoming ICMPv6, neither border nor fw can learn the other's MAC on their shared link, so
no IPv6 packet crosses it. IPv4 still works: ARP is not IP, so the firewall never sees it.

How to see it:
  border:  ip -6 neigh show dev eth3        -> fd00:0:9::2 FAILED / INCOMPLETE
  fw:      tcpdump -ni eth1 icmp6          -> "neighbor solicitation" in, no "neighbor advertisement" out
           nft list ruleset                 -> input chain: no ICMPv6 rule, policy drop
Fix:
  fw:      add back to the input chain (in /etc/nftables.conf, then nft -f /etc/nftables.conf):
             meta l4proto ipv6-icmp accept
           or at least: icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, packet-too-big,
                        destination-unreachable, time-exceeded, parameter-problem, echo-request } accept
Lesson: in IPv4 you can (badly) live without ICMP. In IPv6 you can't: NDP, PMTUD and SLAAC all ride
on ICMPv6. RFC 4890 lists what a firewall must let through.
EOT
}

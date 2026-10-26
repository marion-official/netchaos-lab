# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L3 asymmetric routing + reverse-path filtering"
fault_pick() { P_SP=$(pick spine1 spine2); [ $P_SP = spine1 ] && { P_NH=10.0.1.0; P_DEV=eth1; P_OTHER=eth2; } || { P_NH=10.0.2.0; P_DEV=eth2; P_OTHER=eth1; }; }
fault_ticket() {
  say "Intermittent errors on shop.example.com: some requests are slow or return HTTP 500/503, retries usually work."
  say "BGP is all green and no links are down. Last night the network team applied a 'security baseline'"
  say "and a small 'traffic engineering tweak' somewhere in the fabric."
}
fault_inject() {
  x leaf1 "ip route add 10.10.20.0/24 via $P_NH metric 10 && sysctl -qw net.ipv4.conf.all.rp_filter=1 net.ipv4.conf.$P_OTHER.rp_filter=1"
}
fault_verify() {
  x leaf1 "a=\$(sysctl -n net.ipv4.conf.all.rp_filter); e=\$(sysctl -n net.ipv4.conf.$P_OTHER.rp_filter); m=\$(( a > e ? a : e ));
           [ \$m != 1 ] || ! ip route show exact 10.10.20.0/24 | grep -q 'metric 10'"
}
fault_fix() { x leaf1 "ip route del 10.10.20.0/24 via $P_NH metric 10; sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.$P_OTHER.rp_filter=0"; }
fault_hints() {
  echo "Half fails, half works, nothing is down: think about the paths requests and replies take. Trace web1 -> db1 AND db1 -> web1 (traceroute -n both ways, several times)."
  echo "On leaf1, compare 'ip route show 10.10.20.0/24' with 'vtysh -c \"show ip route 10.10.20.0/24\"'. Then capture on BOTH uplinks: tcpdump -ni eth1 port 5432 and tcpdump -ni eth2 port 5432. Do replies come in on an interface they never leave from?"
  echo "Packets arrive on leaf1 and vanish without any firewall. Which kernel feature drops packets whose source isn't reachable via the interface they came in on? (sysctl -a | grep rp_filter ; nstat -az | grep -i rpfilter)"
}
fault_solution() { cat <<EOT
ROOT CAUSE (two changes that are each harmless alone):
  1. leaf1 has a static route "10.10.20.0/24 via $P_NH metric 10" (the "traffic engineering tweak"),
     so all traffic from VLAN 10 to db1 leaves via $P_SP only.
  2. leaf1 has strict reverse-path filtering (rp_filter=1, the "security baseline").
db1's replies come back through leaf2, which still load-balances (ECMP) across BOTH spines. Replies
arriving on leaf1:$P_OTHER fail the strict check ("my route back to 10.10.20.10 is via $P_DEV, not
$P_OTHER") and are silently dropped. Which flows hash onto which spine is per connection -> ~50% fail.

How to see it:
  leaf1:  ip route show 10.10.20.0/24        -> the static route (metric 10) beats BGP (metric 20)
          tcpdump on $P_DEV and $P_OTHER         -> requests out on $P_DEV, some replies in on $P_OTHER, never forwarded
          sysctl net.ipv4.conf.{all,$P_OTHER}.rp_filter -> 1 (effective value = max(all, interface))
          nstat -az TcpExtIPReversePathFilter (or IPReversePathFilter) -> counter increasing
Fix (either removes the problem; doing both restores the intended design):
  leaf1:  ip route del 10.10.20.0/24 via $P_NH metric 10
          sysctl -w net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.$P_OTHER.rp_filter=0  (or 2 = loose mode)
Lesson: strict uRPF and asymmetric routing don't mix - in ECMP fabrics use loose mode (2) or none.
And: "only one change was made" is rarely true; look for interactions.
EOT
}

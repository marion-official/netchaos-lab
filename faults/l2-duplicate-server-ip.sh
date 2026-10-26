# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 duplicate IP"
fault_pick() { P_V=$(pick web1 web2); if [ $P_V = web1 ]; then P_C=web2; else P_C=web1; fi; }
fault_ticket() {
  say "HAProxy on lb1 shows backend '$P_V' flapping between UP and DOWN every few seconds."
  say "$P_V itself looks perfectly healthy when the on-call engineer logs in."
  say "Config management ran on the web tier this morning."
}
fault_inject() {
  x $P_C "ip addr add $(ip_of $P_V)/24 dev eth1 && arping -q -U -c 2 -I eth1 $(ip_of $P_V)"
}
fault_verify() { x $P_C "! ip -4 addr show dev eth1 | grep -q ' $(ip_of $P_V)/'"; }
fault_fix() {
  x $P_C "ip addr del $(ip_of $P_V)/24 dev eth1"
  x $P_V "arping -q -U -c 2 -I eth1 $(ip_of $P_V)"
  x lb1  "ip neigh flush dev eth1"
}
fault_hints() {
  echo "Watch the HAProxy log on lb1 (tail -f /var/log/haproxy.log): what's the failure reason when $P_V goes DOWN?"
  echo "On lb1, run 'ip neigh show $(ip_of $P_V)' several times, and compare with $P_V's real MAC (ip link show eth1 on $P_V)."
  echo "arping -I eth1 -c 5 $(ip_of $P_V) from lb1. How many different MACs answer? Then find who owns the other one."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_C has $P_V's address $(ip_of $P_V) configured as a secondary IP on eth1. Both hosts
answer ARP for it, so lb1's ARP cache flips between the two MACs. When it points at $P_C, the health
check reaches a host where nginx doesn't listen on that IP -> TCP RST -> "Connection refused" ->
$P_V marked DOWN, then UP again when ARP flips back. Logging into $P_V shows nothing wrong.

How to see it:
  lb1:   tail -f /var/log/haproxy.log      -> "Layer4 connection problem ... Connection refused"
         ip neigh show $(ip_of $P_V)        -> MAC changes between checks
         arping -I eth1 -c 5 $(ip_of $P_V)  -> replies from two MACs
  $P_C:  ip -br addr                        -> $(ip_of $P_V)/24 as a second address on eth1
Fix:
  $P_C:  ip addr del $(ip_of $P_V)/24 dev eth1
  then:  arping -U -I eth1 $(ip_of $P_V) from $P_V, or flush ARP on lb1 (ip neigh flush dev eth1)
Lesson: "healthy when I log in, failing from outside" -> check WHO you're actually talking to (MAC).
'arping' is the fastest duplicate-IP detector there is (arping -D does duplicate address detection).
EOT
}

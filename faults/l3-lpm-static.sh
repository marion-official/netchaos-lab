# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L3 longest-prefix match"
fault_pick()   { P_R=$(pick leaf1 spine1 spine2); P_PFX=$(pick 10.10.20.0/25 10.10.20.8/29 10.10.20.10/32); P_KIND=$(pick blackhole unreachable); }
fault_ticket() {
  if [ "$P_R" = leaf1 ]; then say "shop.example.com returns HTTP 503 for ALL customers."
  else say "Intermittent HTTP 500/503 on shop.example.com: roughly half of the requests fail."; fi
  say "BGP is fine, all sessions Established, db1 is healthy and pings fine from leaf2."
  say "Last night's maintenance on $([ $P_R = leaf1 ] && echo 'the leaves' || echo 'the spines') 'was rolled back completely'."
}
fault_inject() { x $P_R "ip route add $P_KIND $P_PFX"; }
fault_verify() { x $P_R "! ip route show $P_PFX | grep -q ."; }
fault_fix()    { x $P_R "ip route del $P_PFX"; }
fault_hints() {
  echo "Trace the path from a web server to db1: traceroute -n 10.10.20.10 (repeat it - ECMP may send you different ways). Where does it stop?"
  echo "On that box, ask the kernel the exact question: ip route get 10.10.20.10. Compare with vtysh -c 'show ip route 10.10.20.10'."
  echo "A route to 10.10.20.0/24 exists, but the kernel doesn't use it for that address. Which rule picks the route when several match? 'ip route show' (no filter) and look for anything more specific."
}
fault_solution() { cat <<EOT
ROOT CAUSE: a leftover static route "$P_KIND $P_PFX" on $P_R (added in the kernel directly, outside
FRR). It's MORE SPECIFIC than the BGP /24, so longest-prefix match picks it for db1 (10.10.20.10)
and the packets are discarded$([ "$P_KIND" = unreachable ] && echo " with ICMP unreachable" || echo " silently").
$([ $P_R = leaf1 ] && echo "leaf1 is the web servers' gateway, so every DB request fails." || echo "Only flows hashed via $P_R by ECMP fail, so it's intermittent.")

How to see it:
  web1:  traceroute -n 10.10.20.10 -> dies at $P_R$([ "$P_KIND" = unreachable ] && echo " (!N / !H)")
  $P_R:  ip route get 10.10.20.10 -> $P_KIND
         ip route show            -> "$P_KIND $P_PFX"
         vtysh -c 'show ip route' -> K>* $P_PFX (K = kernel route, FRR sees it too)
Fix:
  $P_R:  ip route del $P_PFX
Lesson: the router uses the MOST SPECIFIC matching route, regardless of protocol or distance.
"ip route get <dst>" answers "what will the kernel actually do" - use it before reading tables by eye.
EOT
}

# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L3 routing protocol (BGP advertisement)"
fault_pick()   { P_NET=$(pick 10.10.20.0/24 10.10.30.0/24); }
fault_ticket() {
  say "shop.example.com returns HTTP 503 for ALL customers."
  say "Network monitoring is green: all BGP sessions Established, no interface errors."
  say "The network team says 'we only did a cosmetic cleanup of the leaf BGP configs'."
}
fault_inject() { x leaf2 "vtysh -c 'conf t' -c 'router bgp 65102' -c 'address-family ipv4 unicast' -c 'no network $P_NET' -c 'end'"; }
fault_verify() { x spine1 "vtysh -c 'show ip route $P_NET json' | jq -e 'has(\"$P_NET\")' >/dev/null"; }
fault_fix()    { x leaf2 "vtysh -c 'conf t' -c 'router bgp 65102' -c 'address-family ipv4 unicast' -c 'network $P_NET' -c 'end'"; }
fault_hints() {
  echo "Which server can't be reached, from where? Ping it from a web server, then from its own leaf. Then traceroute."
  echo "Look at the routing table of the box where the traceroute dies: vtysh -c 'show ip route'. Is the destination subnet there? What does the box do with packets it has no specific route for?"
  echo "Who should be telling the fabric about that subnet? Check what that leaf ADVERTISES: vtysh -c 'show bgp ipv4 unicast neighbors 10.0.1.0 advertised-routes'"
}
fault_solution() { cat <<EOT
ROOT CAUSE: leaf2 stopped advertising $P_NET into BGP ('network $P_NET' removed from its running
config). Sessions stay Established, but the spines and leaf1 have no route to that subnet. Their
traffic follows the default route to border -> fw, where it dies.

How to see it:
  web1:    traceroute -n <server in $P_NET> -> goes via spine -> border -> fw... wrong way
  spine1:  vtysh -c 'show ip route $P_NET'            -> "Network not in table" (only 0.0.0.0/0 matches)
  leaf2:   vtysh -c 'show bgp ipv4 unicast'           -> $P_NET not there (it's still a connected route!)
           vtysh -c 'show running-config' vs /etc/frr/frr.conf -> running and startup config differ
Fix:
  leaf2:   vtysh -c 'conf t' -c 'router bgp 65102' -c 'address-family ipv4 unicast' -c 'network $P_NET'
           (restarting FRR also "fixes" it, because the startup config is still correct - find out WHY first)
Lesson: "sessions up" says nothing about WHAT is exchanged. Check advertised/received routes.
Also: a default route turns "no route" into "wrong route" - failures look like the edge's fault.
EOT
}

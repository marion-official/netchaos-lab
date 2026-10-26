# SPOILER: fault definition. Needs dual-stack mode (./labctl up --ipv6).
FAULT_LEVEL=2
FAULT_LAYER="L3 IPv6 routing (MP-BGP address families)"
fault_supported() { ipv6_on; }
fault_pick() {
  P_R=$(pick leaf1 border); [ $P_R = leaf1 ] && P_AS=65101 || P_AS=65103
  P_NBRS=$(x $P_R "vtysh -c 'show bgp ipv6 unicast summary json' | jq -r '.peers | keys[]' | tr '\n' ' '")
}
fault_ticket() {
  say "IPv6 monitoring: shop.example.com is unreachable over IPv6 from the internet."
  say "IPv4 customers are fine. All BGP alarms are green."
  say "The network team 'refactored the BGP templates' for IPv6 yesterday."
}
fault_inject() {
  local c="vtysh -c 'conf t' -c 'router bgp $P_AS' -c 'address-family ipv6 unicast'" n
  for n in $P_NBRS; do c+=" -c 'no neighbor $n activate'"; done
  x $P_R "$c"
}
fault_verify() {
  x $P_R "vtysh -c 'show bgp ipv6 unicast summary json' | jq -e '(.peers | length) >= 2 and ([.peers[].state] | all(. == \"Established\"))' >/dev/null"
}
fault_fix() {
  local c="vtysh -c 'conf t' -c 'router bgp $P_AS' -c 'address-family ipv6 unicast'" n
  for n in $P_NBRS; do c+=" -c 'neighbor $n activate'"; done
  x $P_R "$c"
}
fault_hints() {
  echo "Walk the IPv6 path like you would IPv4: from inet-client 'curl -6 -v http://shop.example.com/', 'traceroute -6 -n 2001:db8:10:10::10', then ping -6 hop by hop."
  echo "On the fabric routers compare 'vtysh -c \"show ip route\"' with 'vtysh -c \"show ipv6 route\"'. Which router is missing which IPv6 prefixes? Who should be advertising them?"
  echo "'show bgp summary' and 'show bgp ipv6 unicast summary' are different views. On the suspect router: 'show bgp neighbor <v6 neighbor>' - look for the address families listed for that session."
}
fault_solution() { cat <<EOT
ROOT CAUSE: on $P_R the IPv6 BGP neighbors ($P_NBRS) are no longer ACTIVATED in
'address-family ipv6 unicast'. A BGP session only exchanges routes for the address families
activated on it. With no family active, those sessions don't come up at all - and since they are
separate from the IPv4 sessions, every IPv4 alarm stays green.

How to see it:
  spine1:  vtysh -c 'show ipv6 route'            -> $([ $P_R = leaf1 ] && echo "no 2001:db8:10:10::/64 (VLAN 10)" || echo "no ::/0 default")
  $P_R:    vtysh -c 'show bgp ipv6 unicast summary' -> no neighbors
           vtysh -c 'show running-config'        -> neighbors defined under 'router bgp', but no 'activate'
                                                    in 'address-family ipv6 unicast'
Fix:
  $P_R:    vtysh -c 'conf t' -c 'router bgp $P_AS' -c 'address-family ipv6 unicast' \\
                 -c 'neighbor <each v6 neighbor> activate'
           (on a real box also 'write memory')
Lesson: in multiprotocol BGP every address family is opt-in per neighbor. Monitor per-AF prefix
counts, not just "session up". Dual-stack = two of everything that can break independently.
EOT
}

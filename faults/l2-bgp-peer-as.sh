# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 routing protocol (BGP)"
fault_pick() {
  P_SP=$(pick spine1 spine2); P_LEAF=$(pick leaf1 leaf2 border)
  case $P_LEAF in leaf1) P_AS=65101; P_I=1;; leaf2) P_AS=65102; P_I=3;; border) P_AS=65103; P_I=5;; esac
  [ $P_SP = spine1 ] && P_NB=10.0.1.$P_I || P_NB=10.0.2.$P_I
  P_BAD=$((P_AS + 10))
}
fault_ticket() {
  say "Monitoring alert: 'BGP neighbour down' raised on the fabric. No customer impact reported yet."
  say "A change to add a new rack's ASN plan was pushed to the spines this morning."
}
fault_inject() { x $P_SP "vtysh -c 'conf t' -c 'router bgp 65000' -c 'neighbor $P_NB remote-as $P_BAD' -c 'end' -c 'clear bgp $P_NB'"; }
fault_verify() { x $P_SP "vtysh -c 'show bgp neighbor $P_NB json' | jq -e '.[\"$P_NB\"].bgpState == \"Established\"' >/dev/null"; }
fault_fix()    { x $P_SP "vtysh -c 'conf t' -c 'router bgp 65000' -c 'neighbor $P_NB remote-as $P_AS' -c 'end' -c 'clear bgp $P_NB'"; }
fault_hints() {
  echo "Which session? On every fabric box: vtysh -c 'show bgp summary'. Both ends of a session tell you something."
  echo "vtysh -c 'show bgp neighbor <ip>' shows the last error. /var/log/frr/frr.log too. tcpdump -ni <iface> port 179 -v shows the OPEN and NOTIFICATION messages."
  echo "In an OPEN message each side announces its own AS. Compare with what the other side is configured to expect (show running-config)."
}
fault_solution() { cat <<EOT
ROOT CAUSE: on $P_SP, neighbor $P_NB ($P_LEAF) is configured with remote-as $P_BAD, but $P_LEAF is AS $P_AS.
$P_SP rejects $P_LEAF's OPEN with NOTIFICATION "Bad Peer AS". Traffic still flows via the other spine
(that's what ECMP redundancy is for), so customers don't notice - yet.

How to see it:
  $P_SP:   vtysh -c 'show bgp summary'          -> $P_NB not Established (Active/Connect)
           vtysh -c 'show bgp neighbor $P_NB'   -> "Last reset ... Bad Peer AS" / remote AS $P_BAD
           tcpdump -ni <iface> -v port 179      -> OPEN "my AS $P_AS", then NOTIFICATION
Fix:
  $P_SP:   vtysh -c 'conf t' -c 'router bgp 65000' -c 'neighbor $P_NB remote-as $P_AS'
           (and 'write memory' on a real box, or it comes back after a reboot)
Lesson: redundancy hides failures. Alerts on "lost redundancy" matter as much as "outage".
EOT
}

# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L2 duplicate MAC / bridge FDB"
fault_pick() {
  local pair; pair=$(pick "web2 web1" "web1 web2" "web1 lb1" "web2 lb1")
  P_CULPRIT=${pair% *}; P_VICTIM=${pair#* }
  P_VMAC=$(x $P_VICTIM "cat /sys/class/net/eth1/address")
  P_CMAC=$(x $P_CULPRIT "cat /sys/class/net/eth1/address")
}
fault_refresh() {   # after 'labctl recover': interfaces have new MACs
  P_VMAC=$(x $P_VICTIM "cat /sys/class/net/eth1/address")
  P_CMAC=$(x $P_CULPRIT "cat /sys/class/net/eth1/address")
}
fault_ticket() {
  if [ "$P_VICTIM" = lb1 ]; then
    say "shop.example.com is flaky for customers: some requests hang or fail, a retry often works."
  else
    say "HAProxy on lb1 keeps flapping backend servers between UP and DOWN. Customers see occasional errors."
  fi
  say "No config changes on the servers. The virtualization team did 'some VM maintenance' overnight."
}
fault_inject() {
  x $P_CULPRIT "ip link set dev eth1 address $P_VMAC && arping -q -c 2 -I eth1 10.10.10.1"
}
fault_verify() { [ "$(x $P_CULPRIT 'cat /sys/class/net/eth1/address')" != "$P_VMAC" ]; }
fault_fix() {
  x $P_CULPRIT "ip link set dev eth1 address $P_CMAC"
  x $P_VICTIM  "arping -q -U -c 2 -I eth1 $(ip_of $P_VICTIM)"
  x $P_CULPRIT "arping -q -U -c 2 -I eth1 $(ip_of $P_CULPRIT)"
}
fault_hints() {
  echo "Intermittent, and IPs look correct everywhere. Go below L3: compare 'ip neigh' on lb1 and leaf1 with what each server says its own MAC is (ip -br link)."
  echo "Ask the switch where it thinks each MAC lives: on leaf1 'bridge fdb show | grep -v permanent', several times. Does any entry move between ports? ('bridge monitor fdb' shows it live.)"
  echo "tcpdump -eni eth1 on the servers in VLAN 10: are frames arriving that carry another server's IP?"
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_CULPRIT's eth1 has the SAME MAC address as $P_VICTIM ($P_VMAC) - the classic result of
cloning a VM without regenerating its MAC. leaf1's bridge can store only one port per MAC, so its
forwarding table (FDB) flips to whichever of the two sent the last frame. While it points at
$P_CULPRIT, frames meant for $P_VICTIM are delivered to $P_CULPRIT, which discards them (wrong IP).
IP config, ARP and routes all look "correct" - the problem is purely L2.

How to see it:
  leaf1:      bridge fdb show | grep $P_VMAC     -> the port changes over time ; bridge monitor fdb
  servers:    ip -br link                         -> two servers with the same MAC on eth1
  lb1/leaf1:  ip neigh                            -> two different IPs resolving to the same MAC
  $P_CULPRIT: tcpdump -eni eth1 'not host $(ip_of $P_CULPRIT)' -> unicast frames for $(ip_of $P_VICTIM)
Fix:
  $P_CULPRIT: ip link set dev eth1 address $P_CMAC   (any unique, locally-administered MAC works)
  Then make the switch relearn: traffic from $P_VICTIM (arping -U -I eth1 $(ip_of $P_VICTIM)), or flush the
  FDB on leaf1 (ip link set dev <bridge> type bridge fdb_flush). Otherwise the stale entry can keep
  sending $P_VICTIM's frames to the wrong port until it ages out (300 s by default).
Lesson: same IP -> ARP fights. Same MAC -> the SWITCH fights (MAC flapping). Real switches log
"MAC move/flap" for exactly this; on Linux it's 'bridge monitor fdb'.
EOT
}

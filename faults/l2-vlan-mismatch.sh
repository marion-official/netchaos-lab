# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L2 VLAN"
fault_pick() {
  P_T=$(pick db1 dns1); P_PORT=$(port_of $P_T); P_VLAN=$(vlan_of $P_T)
  if [ "$P_VLAN" = 20 ]; then P_WRONG=30; else P_WRONG=20; fi
}
fault_ticket() { ticket_by_target "$P_T"; say "The network team did 'port cleanup' on the leaf switches last night."; }
# works on both a VLAN-aware bridge (br0) and the one-bridge-per-VLAN fallback
fault_inject() {
  x leaf2 "if [ \$(cat /run/vlan-mode) = aware ]; then
             bridge vlan del dev $P_PORT vid $P_VLAN; bridge vlan add dev $P_PORT vid $P_WRONG pvid untagged
           else ip link set $P_PORT master vlan$P_WRONG; fi"
}
fault_verify() {
  x leaf2 "if [ \$(cat /run/vlan-mode) = aware ]; then
             bridge vlan show dev $P_PORT | grep -Eq '(^|[[:space:]])${P_VLAN}[[:space:]]+PVID' &&
             ! bridge vlan show dev $P_PORT | grep -Eq '(^|[[:space:]])$P_WRONG([[:space:]]|\$)'
           else [ \"\$(basename \$(readlink /sys/class/net/$P_PORT/master))\" = vlan$P_VLAN ]; fi"
}
fault_fix() {
  x leaf2 "if [ \$(cat /run/vlan-mode) = aware ]; then
             bridge vlan del dev $P_PORT vid $P_WRONG; bridge vlan add dev $P_PORT vid $P_VLAN pvid untagged
           else ip link set $P_PORT master vlan$P_VLAN; fi"
}
fault_hints() {
  echo "Start on $P_T: link up? IP and gateway right? Can it ping its own gateway $(echo $(ip_of $P_T) | cut -d. -f1-3).1?"
  echo "Link is up but the gateway doesn't answer ARP: 'ip neigh' on $P_T, and 'tcpdump -eni eth1 arp' on $P_T while pinging. Does the ARP request reach the switch? Does the right SVI see it?"
  echo "On leaf2: 'bridge vlan show' (or 'bridge link' if it prints nothing) - which VLAN / bridge is $P_PORT in?"
}
fault_solution() { cat <<EOT
ROOT CAUSE: switch port leaf2:$P_PORT (facing $P_T) was moved from VLAN $P_VLAN to VLAN $P_WRONG.
$P_T's ARP requests for its gateway now land in the wrong broadcast domain, so nobody answers:
link up, IP config correct, but it can't reach even its default gateway.

How to see it:
  $P_T:   ip neigh              -> gateway INCOMPLETE/FAILED
          tcpdump -eni eth1 arp -> "who-has <gw>" repeated, no reply
  leaf2:  tcpdump -eni vlan$P_WRONG arp   -> the requests show up in the WRONG VLAN
          bridge vlan show     (VLAN-aware bridge)   or   bridge link  (per-VLAN bridges)
Fix (VLAN-aware bridge):
  leaf2:  bridge vlan del dev $P_PORT vid $P_WRONG
          bridge vlan add dev $P_PORT vid $P_VLAN pvid untagged
Fix (fallback mode):  ip link set $P_PORT master vlan$P_VLAN
Lesson: "can't ping my own gateway" with the link up is almost always L2: VLAN, cabling, or ARP.
EOT
}

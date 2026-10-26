# SPOILER: fault definition. Don't read the faults/ folder if you want to learn.
FAULT_LEVEL=1
FAULT_LAYER="L1 physical"
fault_pick()   { P_T=$(pick web1 web2 db1 dns1 lb1); P_LEAF=$(leaf_of $P_T); P_PORT=$(port_of $P_T); }
fault_ticket() { ticket_by_target "$P_T"; }
fault_inject() { x $P_LEAF "ip link set $P_PORT down"; }
fault_verify() { x $P_LEAF "ip link show $P_PORT | grep -q 'state UP'"; }
fault_fix()    { x $P_LEAF "ip link set $P_PORT up"; }
fault_hints() {
  echo "Walk the request path hop by hop: inet-client -> fw -> lb1 -> web -> db1/dns1. Where does it stop working?"
  echo "On the broken server look at the link itself: 'ip -br link', 'ip -s link show eth1'. Is there a carrier (LOWER_UP)?"
  echo "The other end of the cable is a switch port on $P_LEAF. Check it with 'ip -br link' and 'bridge link'."
}
fault_solution() { cat <<EOT
ROOT CAUSE: switch port $P_LEAF:$P_PORT (facing $P_T) was administratively shut down.

How to see it:
  on $P_T:      ip -br link          -> eth1 is 'LOWERLAYERDOWN'/NO-CARRIER: no link partner
  on $P_LEAF:   ip -br link          -> $P_PORT is DOWN (not LOWERLAYERDOWN: someone did 'set down')
Fix:
  on $P_LEAF:   ip link set $P_PORT up
Lesson: always check L1 first. "state DOWN" on your side with NO-CARRIER means look at the far end.
EOT
}

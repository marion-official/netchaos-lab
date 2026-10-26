# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 host routing"
fault_pick()   { P_T=$(pick web1 web2 db1); P_NET=$(ip_of $P_T | cut -d. -f1-3); P_BAD=$(pick 254 100 2); }
fault_ticket() { ticket_by_target "$P_T"; say "Some servers were rebuilt from a new template yesterday."; }
fault_inject() { x $P_T "ip route replace default via $P_NET.$P_BAD"; }
fault_verify() { x $P_T "ip route show default | grep -q 'via $P_NET.1 '"; }
fault_fix()    { x $P_T "ip route replace default via $P_NET.1"; }
fault_hints() {
  echo "From $P_T, what can you reach? Something in its own subnet? Something in another subnet? The difference is the router."
  echo "'ip route' on $P_T. Then 'ip neigh' - is the next hop resolved? Who owns that IP?"
  echo "The real gateway of $P_NET.0/24 is the leaf's SVI. Check which IP that is (ip -br addr on the leaf)."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_T's default route points to $P_NET.$P_BAD, which doesn't exist. The real gateway is $P_NET.1.
Same-subnet traffic still works (it doesn't use the gateway), which is why some checks look fine.

How to see it:
  $P_T:  ip route             -> default via $P_NET.$P_BAD
         ip neigh             -> $P_NET.$P_BAD FAILED / INCOMPLETE
         ping $P_NET.1        -> works (it's on-link), ping 10.10.30.10 -> fails
Fix:
  $P_T:  ip route replace default via $P_NET.1
Lesson: ARP state for the next hop tells you instantly whether your gateway exists.
EOT
}

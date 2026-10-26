# SPOILER: fault definition. Needs dual-stack mode (./labctl up --ipv6).
FAULT_LEVEL=3
FAULT_LAYER="L2/L3 IPv6 duplicate address detection"
fault_supported() { ipv6_on; }
fault_pick() { P_C=$(pick web1 web2); }
fault_ticket() {
  say "lb1 was rebooted for kernel patching. Since then IPv6 customers get 'connection refused'."
  say "IPv4 customers are fine. lb1 'came back clean', HAProxy is running and listening on :::80."
}
fault_inject() {
  x $P_C "ip -6 addr add 2001:db8:10:10::10/64 dev eth1 nodad"
  x lb1 "ip -6 addr del 2001:db8:10:10::10/64 dev eth1; ip -6 addr add 2001:db8:10:10::10/64 dev eth1; sleep 3; ip -6 route replace default via 2001:db8:10:10::1 2>/dev/null; true"
  x leaf1 "ip -6 neigh flush dev vlan10"
}
fault_verify() {
  x $P_C "! ip -6 addr show dev eth1 | grep -q '2001:db8:10:10::10/'" &&
  x lb1 "ip -6 addr show dev eth1 | grep '2001:db8:10:10::10/' | grep -vqE 'dadfailed|tentative'"
}
fault_fix() {
  x $P_C "ip -6 addr del 2001:db8:10:10::10/64 dev eth1"
  x lb1 "ip -6 addr del 2001:db8:10:10::10/64 dev eth1; ip -6 addr add 2001:db8:10:10::10/64 dev eth1; sleep 3; ip -6 route replace default via 2001:db8:10:10::1"
  x leaf1 "ip -6 neigh flush dev vlan10"
}
fault_hints() {
  echo "'Connection refused' means some host answered with a TCP RST. Capture it on the fw inside interface or on leaf1 with MACs: tcpdump -eni <iface> 'ip6 and tcp'. Whose MAC sent the RST?"
  echo "On lb1, look at its IPv6 addresses carefully: ip -6 addr show dev eth1. Every word on those lines means something."
  echo "IPv6 checks that an address is unique before using it (DAD). If the check fails, who else is claiming 2001:db8:10:10::10? 'ip -6 neigh' on leaf1, then 'ip -6 addr' on the servers in VLAN 10."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_C has lb1's IPv6 address 2001:db8:10:10::10 configured (added with 'nodad', so it never
checked). When lb1 rebooted and re-added its own address, Duplicate Address Detection found $P_C
already answering for it, and the kernel marked lb1's address "dadfailed": lb1 will not use it.
So every IPv6 customer connection goes to $P_C, where nothing listens on port 80 -> RST.
HAProxy "listening on :::80" is true but useless: the address never arrives at lb1.

How to see it:
  lb1:    ip -6 addr show dev eth1   -> "inet6 2001:db8:10:10::10/64 scope global dadfailed tentative"
  leaf1:  ip -6 neigh show 2001:db8:10:10::10 -> MAC of $P_C, not lb1
  fw:     tcpdump -eni eth1 'ip6 and tcp[13] & 4 != 0' -> RSTs (the MAC trail leads to $P_C)
  $P_C:   ip -6 addr                 -> 2001:db8:10:10::10/64 (no 'tentative', because nodad)
Fix:
  $P_C:   ip -6 addr del 2001:db8:10:10::10/64 dev eth1
  lb1:    re-add the address so DAD runs again, then the default route:
          ip -6 addr del 2001:db8:10:10::10/64 dev eth1 ; ip -6 addr add 2001:db8:10:10::10/64 dev eth1
          ip -6 route replace default via 2001:db8:10:10::1
  leaf1:  ip -6 neigh flush dev vlan10   (or wait for the stale entry to expire)
Lesson: IPv6 protects the FIRST holder of an address and quietly disables the newcomer - here the
legitimate server. 'dadfailed' is easy to miss; always read the flags in 'ip -6 addr'.
EOT
}

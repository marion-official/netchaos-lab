# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 IPv4 addressing (subnet mask)"
fault_pick() { P_T=$(pick web1 web2); P_LEN=$(pick 16 12 8); }
fault_ticket() { ticket_by_target "$P_T"; say "$P_T's network config was 'standardised' by a new provisioning template."; }
fault_inject() {
  x $P_T "ip addr del $(ip_of $P_T)/24 dev eth1 && ip addr add $(ip_of $P_T)/$P_LEN dev eth1 && ip route replace default via 10.10.10.1"
}
fault_verify() { x $P_T "ip -4 -o addr show dev eth1 | grep -q ' $(ip_of $P_T)/24 '"; }
fault_fix() {
  x $P_T "ip addr del $(ip_of $P_T)/$P_LEN dev eth1; ip addr add $(ip_of $P_T)/24 dev eth1; ip route replace default via 10.10.10.1"
}
fault_hints() {
  echo "Can $P_T reach things in its own subnet? Things in other subnets? Note exactly which work and which don't."
  echo "Ask the kernel how it would reach db1: 'ip route get 10.10.20.10' on $P_T. Via a gateway, or directly? Compare with the other web server."
  echo "'ip neigh' and 'tcpdump -eni eth1 arp' on $P_T while it tries to reach db1: who is it ARPing for? Then look closely at ip -br addr."
}
fault_solution() { cat <<EOT
ROOT CAUSE: $P_T has $(ip_of $P_T)/$P_LEN instead of /24. With the mask that wide, the kernel believes
db1 (10.10.20.10) and dns1 (10.10.30.10) are on the SAME link, so it never uses the gateway: it ARPs
for them directly on VLAN 10, nobody answers, and DNS + DB connections fail. lb1 (same /24) still
reaches $P_T fine, so the box looks "up".

How to see it:
  $P_T:  ip -br addr                -> $(ip_of $P_T)/$P_LEN
         ip route get 10.10.20.10   -> "dev eth1 src ..." with NO "via 10.10.10.1"
         ip neigh                   -> 10.10.20.10 / 10.10.30.10 INCOMPLETE/FAILED
         tcpdump -eni eth1 arp      -> "who-has 10.10.20.10" (should be who-has 10.10.10.1)
Fix:
  $P_T:  ip addr del $(ip_of $P_T)/$P_LEN dev eth1 ; ip addr add $(ip_of $P_T)/24 dev eth1
         ip route replace default via 10.10.10.1   (deleting the address also deleted the default route)
Lesson: the mask decides "local vs via the router". Too wide -> remote hosts look local and get ARPed;
too narrow -> local hosts (or even the gateway) look remote. 'ip route get' shows the decision.
EOT
}

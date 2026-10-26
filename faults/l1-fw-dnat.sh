# SPOILER: fault definition.
FAULT_LEVEL=1
FAULT_LAYER="L3/L4 NAT"
fault_pick()   { P_PORT=$(pick 8080 8000 443); }
fault_ticket() {
  say "shop.example.com times out for ALL customers on the internet."
  say "Internal synthetic checks (from inside the DC to lb1) are green."
}
fault_inject() { x fw "sed -i 's/dnat to \$SHOP_LB:80/dnat to \$SHOP_LB:$P_PORT/' /etc/nftables.conf && nft -f /etc/nftables.conf"; }
fault_verify() { x fw "nft list chain ip nat prerouting | grep -q 'dnat to 10.10.10.10:80\$'"; }
fault_fix()    { x fw "sed -i 's/dnat to \$SHOP_LB:$P_PORT/dnat to \$SHOP_LB:80/' /etc/nftables.conf && nft -f /etc/nftables.conf"; }
fault_hints() {
  echo "Inside works, outside doesn't: the fault is between the internet and lb1. Which box sits there?"
  echo "tcpdump on the fw's outside (eth2) and inside (eth1) interfaces at the same time. Does the SYN come in? Does it go out? Rewritten to what?"
  echo "nft list ruleset on fw - read the nat table and compare with what lb1 listens on (ss -ltn on lb1). 'conntrack -L' shows the translation."
}
fault_solution() { cat <<EOT
ROOT CAUSE: the DNAT rule on fw translated 203.0.113.10:80 to 10.10.10.10:$P_PORT instead of :80.
The forward chain only allows tcp/80 to lb1, so the translated packet hit the default drop policy
(the 'dropped by default policy' counter goes up) -> customers see a timeout, not a refusal.

How to see it:
  fw:  tcpdump -ni eth2 port 80   -> SYNs arrive from 203.0.113.100
       tcpdump -ni eth1           -> nothing leaves (dropped)
       nft list ruleset           -> 'dnat to \$SHOP_LB:$P_PORT' ; counters on the drop rule
       conntrack -L -p tcp        -> dst translated to 10.10.10.10 dport=$P_PORT
Fix:
  fw:  edit /etc/nftables.conf back to 'dnat to \$SHOP_LB:80' ; nft -f /etc/nftables.conf
Lesson: capture on both sides of a middlebox. "Goes in, doesn't come out" localises the fault to that box.
EOT
}

# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L4 host firewall"
fault_pick()   { P_T=$(pick web1 web2); if [ $P_T = web1 ]; then P_OK=web2; else P_OK=web1; fi; }
fault_ticket() { ticket_by_target "$P_T"; say "The security team tightened database firewall rules this week."; }
fault_inject() { x db1 "sed -i 's#ip saddr 10.10.10.0/24 tcp dport 5432#ip saddr $(ip_of $P_OK) tcp dport 5432#' /etc/nftables.conf && nft -f /etc/nftables.conf"; }
fault_verify() { x $P_T "nc -z -w 2 10.10.20.10 5432"; }
fault_fix()    { x db1 "sed -i 's#ip saddr $(ip_of $P_OK) tcp dport 5432#ip saddr 10.10.10.0/24 tcp dport 5432#' /etc/nftables.conf && nft -f /etc/nftables.conf"; }
fault_hints() {
  echo "Why does HAProxy think $P_T is unhealthy? curl its /health from lb1 and read the body. Then read /var/log/app/app.log on $P_T."
  echo "Can $P_T reach db1 at all? ping, then 'nc -zv db1.dc.lab 5432'. Compare with the other web server. What does 'No route to host' mean when ping works?"
  echo "tcpdump -ni eth1 port 5432 or icmp on db1 while $P_T retries. Then look at db1's firewall: nft list ruleset"
}
fault_solution() { cat <<EOT
ROOT CAUSE: db1's host firewall (/etc/nftables.conf) only allows $(ip_of $P_OK) to reach tcp/5432
instead of the whole web tier 10.10.10.0/24. $P_T is rejected with ICMP admin-prohibited, which
the app reports as "No route to host" even though routing is fine.

How to see it:
  $P_T:  tail /var/log/app/app.log  -> could not connect ... No route to host
         ping db1 -> OK ; nc -zv db1 5432 -> "No route to host"
  db1:   tcpdump -ni eth1 'port 5432 or icmp' -> SYN in, ICMP "admin prohibited" out
         nft list ruleset -> the accept rule and the counter on the reject rule
Fix:
  db1:   restore 'ip saddr 10.10.10.0/24 tcp dport 5432 accept' in /etc/nftables.conf ; nft -f /etc/nftables.conf
Lesson: error strings lie. "No route to host" can be a firewall REJECT. tcpdump shows the truth.
Also: REJECT fails fast (visible), DROP times out (silent) - know which one your firewall uses.
EOT
}

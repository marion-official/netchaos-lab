# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L7 DNS data"
fault_pick()   { P_BAD=$(pick 10.10.20.11 10.10.20.100 10.10.30.10); }
fault_ticket() { say "shop.example.com returns HTTP 503 for ALL customers."; say "DNS was migrated to a new zone-file workflow yesterday."; }
fault_inject() {
  x dns1 "sed -i -E 's/^(db1[[:space:]]+IN A[[:space:]]+)10.10.20.10/\1$P_BAD/; s/2026092301/2026092302/' /etc/bind/db.dc.lab && svc reload named"
}
fault_verify() { x web1 "[ \"\$(dig +short db1.dc.lab @10.10.30.10)\" = 10.10.20.10 ]"; }
fault_fix() {
  x dns1 "sed -i -E 's/^(db1[[:space:]]+IN A[[:space:]]+)$P_BAD/\110.10.20.10/; s/2026092302/2026092303/' /etc/bind/db.dc.lab && svc reload named"
}
fault_hints() {
  echo "Both web servers are DOWN in HAProxy. What do they have in common? Read /var/log/app/app.log on one of them."
  echo "The app connects to db1 BY NAME. What does that name resolve to? 'getent hosts db1.dc.lab' vs 'dig db1.dc.lab'. Is that really db1? (ssh/exec into db1 and check 'ip -br addr')"
  echo "On dns1: named-checkzone dc.lab /etc/bind/db.dc.lab ; look at /var/log/named/queries.log"
}
fault_solution() { cat <<EOT
ROOT CAUSE: the A record for db1.dc.lab in /etc/bind/db.dc.lab on dns1 points to $P_BAD instead of
10.10.20.10. Every app request resolves the wrong IP and the DB connection fails.

How to see it:
  web1:  tail /var/log/app/app.log  -> connection to $P_BAD failed / timed out
         dig db1.dc.lab +short        -> $P_BAD
  db1:   ip -br addr                  -> 10.10.20.10 (the truth)
Fix:
  dns1:  fix the record, BUMP THE SOA SERIAL, named-checkzone dc.lab /etc/bind/db.dc.lab, svc reload named
Lesson: when "everything" breaks at once, look for the shared dependency (DNS, DB, gateway, auth).
Forgetting the serial bump is a classic: secondaries never pick up the change.
EOT
}

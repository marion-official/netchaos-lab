# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L7 database auth"
fault_pick()   { P_BAD=$(pick 10.10.100.0/24 10.1.10.0/24 10.10.10.0/32); }
fault_ticket() { say "shop.example.com returns HTTP 503 for ALL customers."; say "The DBA applied 'CIS hardening' to PostgreSQL an hour ago."; }
fault_inject() { x db1 "sed -i 's#10.10.10.0/24#$P_BAD#' /etc/postgresql/15/main/pg_hba.conf && pg_ctlcluster 15 main reload"; }
fault_verify() { x web1 "PGPASSWORD=app PGCONNECT_TIMEOUT=3 psql -h db1.dc.lab -U app -d shop -tAc 'select 1' | grep -qx 1"; }
fault_fix()    { x db1 "sed -i 's#$P_BAD#10.10.10.0/24#' /etc/postgresql/15/main/pg_hba.conf && pg_ctlcluster 15 main reload"; }
fault_hints() {
  echo "Network first: can the web servers reach db1:5432? (nc -zv db1.dc.lab 5432). If yes, the problem is above L4."
  echo "Read the app log on a web server, then the PostgreSQL log on db1: /var/log/postgresql/"
  echo "PostgreSQL decides who may connect in pg_hba.conf. Compare each field with the connection that's being refused."
}
fault_solution() { cat <<EOT
ROOT CAUSE: /etc/postgresql/15/main/pg_hba.conf on db1 was changed: the rule for the web tier now
reads $P_BAD instead of 10.10.10.0/24, so connections from web1/web2 match no rule and are refused.

How to see it:
  web1:  tail /var/log/app/app.log -> FATAL: no pg_hba.conf entry for host "10.10.10.11", user "app", database "shop"
  db1:   tail /var/log/postgresql/postgresql-15-main.log -> same message, server side
         grep -v '^#' /etc/postgresql/15/main/pg_hba.conf
Fix:
  db1:   set the ADDRESS back to 10.10.10.0/24 ; pg_ctlcluster 15 main reload
Lesson: TCP connects fine, app still fails -> it's not the network. Stop tcpdumping and read the logs.
EOT
}

# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L7 application release"
fault_pick() { P_T=$(pick web1 web2); P_BUG=$(pick import name dbhost); }
fault_ticket() {
  ticket_by_target "$P_T"
  say "On-call restarted the app on $P_T twice. It didn't help."
  say "The CI pipeline was busy this morning."
}
fault_inject() {
  local sed_expr
  case $P_BUG in
    import) sed_expr='s/^import psycopg2$/import psycopg2\nimport shop_metrics  # 1.4.2: new metrics exporter/' ;;
    name)   sed_expr='s/Server(("127.0.0.1", 8080), Handler)/Server(("127.0.0.1", 8080), RequestHandler)/' ;;
    dbhost) sed_expr='s/host="db1.dc.lab"/host="db01.dc.lab"/' ;;
  esac
  x $P_T "mkdir -p /lab/app/releases && cp /lab/app/app.py /lab/app/releases/app-1.4.1.py &&
          sed -i '$sed_expr' /lab/app/app.py && cp /lab/app/app.py /lab/app/releases/app-1.4.2.py &&
          echo \"\$(date -Is) deploy shop 1.4.2 to \$(hostname): copied releases/app-1.4.2.py -> app.py, restarting app\" >> /var/log/deploy.log &&
          svc restart app; sleep 2; svc restart app"
}
fault_verify() { x $P_T "pgrep -f '[/]lab/app/app.py' >/dev/null && curl -sf -m 5 http://127.0.0.1/health >/dev/null"; }
fault_fix()    { x $P_T "cp /lab/app/releases/app-1.4.1.py /lab/app/app.py && svc restart app"; }
fault_hints() {
  echo "Restarting didn't help, so whatever breaks it happens every time it starts (or on every request). Read the last lines of /var/log/app/app.log right after a restart."
  echo "What changed on $P_T recently? Look around /var/log/ and /lab/app/ (ls -la --time-style=full-iso)."
  echo "Compare the running code with the previous release: diff /lab/app/releases/app-1.4.1.py /lab/app/app.py"
}
fault_solution() { cat <<EOT
ROOT CAUSE: a bad release (shop 1.4.2) was deployed to $P_T (see /var/log/deploy.log).
$(case $P_BUG in
  import) echo "It imports a module that isn't installed (shop_metrics): the app dies at startup with ModuleNotFoundError.";;
  name)   echo "It references a class that doesn't exist (RequestHandler): the app dies at startup with NameError.";;
  dbhost) echo "It points the database at db01.dc.lab, a name that doesn't exist: the app runs, but every request fails (DNS NXDOMAIN), so /health returns 503.";;
esac)
Restarting can't fix a bug that's in the code.

How to see it:
  $P_T:  tail /var/log/app/app.log                     -> the traceback / the DB error, after every restart
         cat /var/log/deploy.log                        -> what changed, and when
         diff /lab/app/releases/app-1.4.1.py /lab/app/app.py  -> the exact change
Fix (rollback first, debug later):
  $P_T:  cp /lab/app/releases/app-1.4.1.py /lab/app/app.py && svc restart app
Lesson: the first question in any incident is "what changed?". If the change is a release,
rolling back is the fastest fix - root-causing the bug can happen after the service is healthy.
EOT
}

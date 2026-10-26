# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L4/L7 port conflict on the app server"
fault_pick() { P_T=$(pick web1 web2); }
fault_ticket() {
  ticket_by_target "$P_T"
  say "Some customers report seeing a strange 'Directory listing' page instead of the shop."
  say "On-call already ran 'svc restart app' on $P_T: no error, but the server is still DOWN."
}
fault_inject() {
  x $P_T "pkill -KILL -f '[/]lab/app/app.py'; mkdir -p /var/tmp/debug && cd /var/tmp/debug && echo 'debug build' > README.txt
          setsid nohup python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 < /dev/null &
          sleep 1; svc start app"
}
fault_verify() {
  x $P_T "pid=\$(pgrep -f '[/]lab/app/app.py' | head -1); [ -n \"\$pid\" ] && ss -Hltnp 'sport = :8080' | grep -q \"pid=\$pid,\""
}
fault_fix() { x $P_T "pkill -f '[h]ttp.server 8080'; sleep 1; svc start app"; }
fault_hints() {
  echo "'svc start' only launches the process in the background - it doesn't tell you whether it survived. Is the app running a few seconds later (svc status)? What did it write in /var/log/app/app.log when it started?"
  echo "Something is answering on the app's port, but it isn't the app. 'ss -ltnp' shows who owns 127.0.0.1:8080. Two processes can have the same name - look at the full command line (ps -fp <pid>, or /proc/<pid>/cmdline and /proc/<pid>/cwd)."
  echo "Compare what nginx gets from its upstream: curl -v http://127.0.0.1:8080/health on $P_T. Who serves directory listings?"
}
fault_solution() { cat <<EOT
ROOT CAUSE: a leftover debug web server ('python3 -m http.server 8080', started from /var/tmp/debug)
is bound to 127.0.0.1:8080 - the port the shop app needs. Restarting the app fails immediately with
"Address already in use", but 'svc start' backgrounds it and reports nothing. nginx keeps proxying
to whoever owns :8080, so customers sometimes get a directory listing and /health returns 404 ->
HAProxy marks $P_T DOWN.

How to see it:
  $P_T:  tail /var/log/app/app.log   -> FATAL [Errno 98] Address already in use
         svc status                   -> app STOPPED (seconds after "restart")
         ss -ltnp 'sport = :8080'     -> python3 pid=X - but ps -fp X shows 'http.server', not app.py
         curl -v 127.0.0.1:8080/health -> 404 from SimpleHTTP
Fix:
  $P_T:  kill the impostor (kill <pid>), then svc start app ; confirm with ss -ltnp and curl 127.0.0.1/health
Lesson: "restart did nothing" = the cause is still there. Never trust a start command's exit code for
a backgrounded service: check the process is alive and owns its port. And: a port's owner is a PID,
not a name - always resolve it to a full command line.
EOT
}

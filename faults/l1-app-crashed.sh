# SPOILER: fault definition.
FAULT_LEVEL=1
FAULT_LAYER="L7 application"
fault_pick()   { P_T=$(pick web1 web2); }
fault_ticket() { ticket_by_target "$P_T"; }
# The process is killed with SIGKILL (what the OOM killer or an operator's 'kill -9' does).
# Nothing deeper is wrong: the lesson is evidence gathering, and saying "unknown" honestly.
fault_inject() { x $P_T "pkill -KILL -f '[/]lab/app/app.py'"; }
fault_verify() { x $P_T "curl -sf -m 3 http://127.0.0.1/health"; }
fault_fix()    { x $P_T "svc start app"; }
fault_hints() {
  echo "What does HAProxy see? From lb1: curl -v http://$(ip_of $P_T)/health"
  echo "A 502 comes from nginx: nginx is alive but its upstream is not. What should be listening on 127.0.0.1:8080? (ss -ltnp)"
  echo "svc status on $P_T, and read /var/log/app/app.log"
}
fault_solution() { cat <<EOT
ROOT CAUSE: the application process on $P_T was killed (SIGKILL). nginx still runs, so HAProxy's
health check (GET /health) gets HTTP 502 and marks the server DOWN.

How to see it:
  lb1:   echo "show stat" | socat - /run/haproxy/admin.sock | cut -d, -f1,2,18,37   (status, last check)
  $P_T:  curl -v 127.0.0.1/health  -> 502 ;  ss -ltnp | grep 8080 -> nothing ;  tail /var/log/app/app.log
Fix:
  $P_T:  svc start app

Why did it die? In THIS exercise nothing deeper was wrong - the process was killed from outside.
What the evidence looks like for that, and how it differs from the alternatives:
  - app.log just stops: no traceback, no shutdown message      -> killed, not crashed in Python
  - dmesg: no "Out of memory: Killed process" / "segfault at" -> not the OOM killer, not a real segfault
  - no core file                                               -> no crash dump
  => honest root cause: "process terminated by an external SIGKILL, source unknown".
In production the next steps would be: who/what can kill it (deploys, cron, OOM in the cgroup:
/sys/fs/cgroup/memory.events), and why nothing restarted it (no supervisor, e.g. systemd
Restart=on-failure) and why nothing alerted on the process itself.
Lesson: 502 = proxy OK, upstream dead. 503 = proxy has no healthy upstream. 504 = upstream too slow.
And "restart fixed it" closes the incident, not the problem.
EOT
}

# SPOILER: fault definition.
FAULT_LEVEL=1
FAULT_LAYER="L4/L7 load balancer config"
fault_pick()   { P_T=$(pick web1 web2); P_PORT=$(pick 8080 8000 443); }
fault_ticket() { ticket_by_target "$P_T"; say "A config change to the load balancer was deployed this morning (change ticket has no details)."; }
fault_inject() {
  x lb1 "sed -i 's/server $P_T \\(10[0-9.]*\\):80\$/server $P_T \\1:$P_PORT/' /etc/haproxy/haproxy.cfg && svc reload haproxy"
}
fault_verify() { x lb1 "echo 'show stat' | socat - /run/haproxy/admin.sock | awk -F, '\$2==\"$P_T\" && \$1==\"be_web\" {print \$18}' | grep -qx UP"; }
fault_fix()    { x lb1 "sed -i 's/server $P_T \\(10[0-9.]*\\):$P_PORT\$/server $P_T \\1:80/' /etc/haproxy/haproxy.cfg && svc reload haproxy"; }
fault_hints() {
  echo "Is the web server itself healthy? Test it directly from lb1: curl -v http://$(ip_of $P_T)/health"
  echo "If the server is fine when YOU test it, compare what you tested with what HAProxy tests. HAProxy's stats socket: echo 'show stat' | socat - /run/haproxy/admin.sock | cut -d, -f1,2,18,37"
  echo "Read /etc/haproxy/haproxy.cfg, and on $P_T run 'ss -ltnp' to see which ports are really open."
}
fault_solution() { cat <<EOT
ROOT CAUSE: in /etc/haproxy/haproxy.cfg on lb1 the backend line for $P_T points to port $P_PORT.
Nothing listens on $(ip_of $P_T):$P_PORT (nginx is on :80, the app only on 127.0.0.1:8080), so the
health check gets "connection refused" (L4CON) and the server is marked DOWN.

How to see it:
  lb1:   echo "show stat" | socat - /run/haproxy/admin.sock | cut -d, -f1,2,18,37  -> DOWN, "Connection refused"
         tail /var/log/haproxy.log   -> "Server be_web/$P_T is DOWN, reason: Layer4 connection problem"
         grep server /etc/haproxy/haproxy.cfg
  $P_T:  ss -ltnp                    -> only :80 and 127.0.0.1:8080
Fix:
  lb1:   set the port back to :80, then  haproxy -c -f /etc/haproxy/haproxy.cfg && svc reload haproxy
Lesson: "works when I test it" + "monitor says down" = you are not testing the same thing. Diff the two.
EOT
}

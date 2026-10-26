# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L7 DNS client"
fault_pick()   { P_T=$(pick web1 web2); P_BAD=$(pick 10.10.30.11 10.10.30.53 10.10.20.10); }
fault_ticket() { ticket_by_target "$P_T"; say "Config management pushed a new base image to some servers."; }
# /etc/resolv.conf is bind-mounted by Docker: rewrite in place (sed -i would fail with "Device or resource busy")
fault_inject() { x $P_T "r=\$(sed 's/^nameserver .*/nameserver $P_BAD/' /etc/resolv.conf) && echo \"\$r\" > /etc/resolv.conf"; }
fault_verify() { x $P_T "grep -q '^nameserver 10.10.30.10\$' /etc/resolv.conf && getent hosts db1.dc.lab >/dev/null"; }
fault_fix()    { x $P_T "r=\$(sed 's/^nameserver .*/nameserver 10.10.30.10/' /etc/resolv.conf) && echo \"\$r\" > /etc/resolv.conf"; }
fault_hints() {
  echo "Read /var/log/app/app.log on $P_T. Is it failing fast or slowly? Time it: time curl -s localhost/health"
  echo "Can $P_T resolve names? 'getent hosts db1.dc.lab' uses the system resolver; 'dig db1.dc.lab' shows which server it asked."
  echo "cat /etc/resolv.conf and compare with the other web server. tcpdump -ni eth1 port 53 shows where queries go."
}
fault_solution() { cat <<EOT
ROOT CAUSE: /etc/resolv.conf on $P_T points to $P_BAD, which is not a DNS server. Every lookup of
db1.dc.lab waits for timeouts and then fails, so /health fails (slowly) and HAProxy marks $P_T DOWN.

How to see it:
  $P_T:  time getent hosts db1.dc.lab -> several seconds, no answer
         dig db1.dc.lab  -> ";; connection timed out; no servers could be reached" (SERVER: $P_BAD)
         tcpdump -ni eth1 port 53 -> queries to $P_BAD, no answers (or ICMP port unreachable)
Fix:
  $P_T:  nameserver 10.10.30.10 in /etc/resolv.conf
         (in a container, 'sed -i' on it fails with "Device or resource busy": the file is a bind mount
          and sed -i replaces the inode. Edit it in place instead, e.g. with vi, or 'cat new > /etc/resolv.conf')
Lesson: a service that is SLOW then fails often means a timeout somewhere - DNS is the usual suspect.
EOT
}

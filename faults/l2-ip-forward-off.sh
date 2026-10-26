# SPOILER: fault definition.
FAULT_LEVEL=2
FAULT_LAYER="L3 router data plane"
fault_pick()   { P_T=$(pick leaf2 leaf1); }
fault_ticket() {
  if [ "$P_T" = leaf2 ]; then say "shop.example.com returns HTTP 503 for ALL customers."
  else say "shop.example.com times out for ALL customers."; fi
  say "Network monitoring is all green: every BGP session is Established."
}
fault_inject() { x $P_T "sysctl -qw net.ipv4.ip_forward=0"; }
fault_verify() { x $P_T "[ \$(sysctl -n net.ipv4.ip_forward) = 1 ]"; }
fault_fix()    { x $P_T "sysctl -qw net.ipv4.ip_forward=1"; }
fault_hints() {
  echo "BGP up does not mean packets flow. Pick one flow that fails and ping/traceroute it hop by hop from the source."
  echo "Find the last hop that answers. tcpdump on that box's in- and out-interface: does the packet come in? Does it go out?"
  echo "The box receives the packet, has a route for it, and still doesn't send it. What makes a Linux box a router? (sysctl -a | grep forward)"
}
fault_solution() { cat <<EOT
ROOT CAUSE: IPv4 forwarding was disabled on $P_T (net.ipv4.ip_forward=0).
The control plane (FRR, BGP) is fine, so all routes and sessions look healthy, but the kernel
drops every packet that isn't addressed to $P_T itself. The box can still ping its neighbours.

How to see it:
  traceroute from a server stops at $P_T (it answers for its own IPs, but forwards nothing)
  $P_T:  tcpdump -ni eth1 icmp  -> packets arrive ; tcpdump -ni <egress>  -> nothing leaves
         sysctl net.ipv4.ip_forward  -> 0
Fix:
  $P_T:  sysctl -w net.ipv4.ip_forward=1   (persist it in /etc/sysctl.d/ on a real box)
Lesson: control plane != data plane. "Routes are there" is not proof packets are forwarded.
EOT
}

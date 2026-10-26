# SPOILER: fault definition.
FAULT_LEVEL=3
FAULT_LAYER="L1/L2 degraded link (latency + loss)"
fault_supported() { x leaf2 "tc qdisc add dev lo root netem delay 1ms 2>/dev/null && tc qdisc del dev lo root"; }
fault_pick()   { P_DELAY=$(pick 150ms 250ms 400ms); P_LOSS=$(pick 2% 5% 8%); }
fault_ticket() {
  say "shop.example.com is SLOW for everyone (several seconds per page), and some requests fail."
  say "CPU and memory on web1, web2 and db1 look normal. Nothing was deployed today."
}
fault_inject() { x leaf2 "tc qdisc replace dev eth3 root netem delay $P_DELAY 30ms loss $P_LOSS"; }
fault_verify() { x leaf2 "! tc qdisc show dev eth3 | grep -q netem"; }
fault_fix()    { x leaf2 "tc qdisc del dev eth3 root"; }
fault_hints() {
  echo "Slow where? Time each piece: curl -w '%{time_connect} %{time_starttransfer} %{time_total}\n' from inet-client, from lb1 to a web server, and localhost/health on a web server."
  echo "It's the DB calls. ping -c 50 db1 from web1: look at rtt min/avg/max/mdev and packet loss. Then ping leaf2's gateway IP. mtr -n db1 shows per hop."
  echo "The slowness appears on the last hop only, but db1 itself is idle. Check every queue on that link, on both ends: tc -s qdisc show dev <iface>"
}
fault_solution() { cat <<EOT
ROOT CAUSE: a tc netem qdisc on leaf2:eth3 (the switch port facing db1) adds $P_DELAY (+/-30ms) latency
and $P_LOSS packet loss. Every app request opens a new DB connection = several round trips, so each
page takes seconds, and lost SYNs/handshakes cause timeouts. db1 itself looks perfectly clean.

How to see it:
  web1:   ping -c 50 db1.dc.lab   -> high rtt, high mdev, loss ; ping 10.10.20.1 (leaf2) -> fast
          mtr -n db1.dc.lab       -> latency appears on the LAST hop only
  leaf2:  tc -s qdisc show dev eth3 -> netem delay $P_DELAY loss $P_LOSS
Fix:
  leaf2:  tc qdisc del dev eth3 root
Lesson: latency added on one hop shows up only from that hop onward - bisect with ping/mtr.
Real-world equivalents: a bad cable/optic (CRC errors -> loss), duplex mismatch, a congested uplink.
Also note how connection reuse (pooling) would have hidden most of this: the app design amplifies RTT.
EOT
}

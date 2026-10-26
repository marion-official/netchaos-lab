#!/bin/bash
# Dual-stack mode: adds IPv6 next to the existing IPv4 config on ONE node.
# labctl pipes this into every node (docker exec -i ... bash -s) after a normal IPv4 boot,
# so the default IPv4 lab is untouched and this file can change without rebuilding the image.
#
# IPv6 plan, derived mechanically from the IPv4 addresses:
#   fabric p2p   10.0.X.Y/31     -> fd00:0:X:(Y/2)::(Y%2+1)/64   (one /64 per link)
#   loopbacks    10.255.A.B/32   -> fd00:255:A::B/128
#   server VLANs 10.10.V.H/24    -> 2001:db8:10:V::H/64          (gateway ::1 = leaf SVI)
#   internet     203.0.113.H/24  -> 2001:db8:113::H/64
# The shop is published on IPv6 WITHOUT NAT: customers reach lb1's own address 2001:db8:10:10::10.
# The app tier (web -> db1) stays IPv4-only, a common real-world state.
set -u
HOST=$(hostname)
log() { echo "[ipv6] $HOST: $*"; }

v4to6() {  # v4to6 <a.b.c.d/len> -> IPv6 address/len, or nothing if not in the plan
  local ip=${1%/*} len=${1#*/} a b c d
  IFS=. read -r a b c d <<<"$ip"
  if   [ "$a.$b" = 10.0 ]   && [ "$len" = 31 ]; then echo "fd00:0:$c:$((d / 2))::$((d % 2 + 1))/64"
  elif [ "$a.$b" = 10.255 ];                    then echo "fd00:255:$c::$d/128"
  elif [ "$a.$b" = 10.10 ]  && [ "$len" = 24 ]; then echo "2001:db8:10:$c::$d/64"
  elif [ "$a.$b.$c" = 203.0.113 ] && [ "$len" = 24 ]; then echo "2001:db8:113::$d/64"
  fi
}
peer6() {  # peer6 <neighbor's IPv4 on a fabric /31> -> the neighbor's IPv6 on that link
  local a b c d; IFS=. read -r a b c d <<<"$1"
  echo "fd00:0:$c:$((d / 2))::$((d % 2 + 1))"
}

# ---- 1. turn IPv6 on (Docker/containerlab may have left it disabled)
sysctl -qw net.ipv6.conf.all.disable_ipv6=0 net.ipv6.conf.default.disable_ipv6=0
for p in /sys/class/net/*; do i=${p##*/}
  [ "$i" = eth0 ] && continue
  sysctl -qw "net.ipv6.conf.$i.disable_ipv6=0" 2>/dev/null
  sysctl -qw "net.ipv6.conf.$i.accept_ra=0" 2>/dev/null   # static addressing: no surprises from RAs
done

# ---- 2. addresses (every IPv4 address in the plan gets an IPv6 twin)
ip -4 -o addr show | awk '$2!="eth0" {print $2, $4}' | while read -r dev cidr; do
  v6=$(v4to6 "$cidr"); [ -n "$v6" ] || continue
  ip -6 addr add "$v6" dev "$dev" 2>/dev/null && log "$dev $v6"
done

# wait for Duplicate Address Detection to finish (addresses are 'tentative' until then)
for _ in $(seq 1 20); do ip -6 addr show tentative | grep -q inet6 || break; sleep 0.5; done

# ---- 3. role specific
case ${ROLE:-} in
router)
  sysctl -qw net.ipv6.conf.all.forwarding=1 net.ipv6.fib_multipath_hash_policy=1
  AS=$(vtysh -c 'show bgp summary json' | jq -r '.ipv4Unicast.as')
  cmds=(-c 'conf t')
  [ "$HOST" = border ] && cmds+=(-c 'ipv6 route ::/0 fd00:0:9::2')
  cmds+=(-c "router bgp $AS")
  peers=$(vtysh -c 'show bgp summary json' | jq -r '.ipv4Unicast.peers | to_entries[] | "\(.key) \(.value.remoteAs)"')
  while read -r p4 ras; do
    p6=$(peer6 "$p4")
    cmds+=(-c "neighbor $p6 remote-as $ras")
    desc=$(vtysh -c "show bgp neighbor $p4 json" | jq -r ".\"$p4\".nbrDesc // empty")
    [ -n "$desc" ] && cmds+=(-c "neighbor $p6 description $desc")
  done <<<"$peers"
  cmds+=(-c 'address-family ipv4 unicast')
  while read -r p4 _; do cmds+=(-c "no neighbor $(peer6 "$p4") activate"); done <<<"$peers"
  cmds+=(-c 'exit-address-family' -c 'address-family ipv6 unicast')
  while read -r p4 _; do cmds+=(-c "neighbor $(peer6 "$p4") activate"); done <<<"$peers"
  # advertise loopback + server VLANs (same as the IPv4 'network' statements)
  for n in $(ip -6 -o addr show scope global | awk '$2=="lo" || $2 ~ /^vlan/ {print $4}'); do
    case $n in
      */128) cmds+=(-c "network $n") ;;
      */64)  cmds+=(-c "network $(python3 -c "import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)" "$n")") ;;
    esac
  done
  [ "$HOST" = border ] && cmds+=(-c 'network ::/0')
  cmds+=(-c 'maximum-paths 8' -c 'exit-address-family' -c 'end' -c 'write memory')
  vtysh "${cmds[@]}" >/dev/null && log "BGP IPv6 sessions + prefixes configured"
  ;;
firewall)
  sysctl -qw net.ipv6.conf.all.forwarding=1
  ip -6 route add 2001:db8:10::/48 via fd00:0:9::1
  ip -6 route add fd00::/16 via fd00:0:9::1
  # IPv6 needs ICMPv6 (neighbour discovery, packet-too-big): allow it in, and allow the shop to lb1.
  # Persisted in /etc/nftables.conf so reloading the file keeps it.
  python3 - <<'PY'
p = "/etc/nftables.conf"; s = open(p).read()
if "ipv6-icmp" not in s:
    s = s.replace('    meta l4proto icmp accept\n',
                  '    meta l4proto icmp accept\n    meta l4proto ipv6-icmp accept comment "NDP, PMTUD"\n', 1)
    s = s.replace('    ct state invalid drop\n',
                  '    ct state invalid drop\n'
                  '    meta l4proto ipv6-icmp accept comment "PMTUD etc."\n'
                  '    iifname $OUTSIDE oifname $INSIDE ip6 daddr 2001:db8:10:10::10 tcp dport 80 accept comment "shop v6 (no NAT)"\n', 1)
    open(p, "w").write(s)
PY
  nft -f /etc/nftables.conf && log "firewall: ICMPv6 + shop v6 rules"
  ;;
db)
  python3 - <<'PY'
p = "/etc/nftables.conf"; s = open(p).read()
if "ipv6-icmp" not in s:
    s = s.replace('    meta l4proto icmp accept\n',
                  '    meta l4proto icmp accept\n    meta l4proto ipv6-icmp accept comment "NDP"\n', 1)
    open(p, "w").write(s)
PY
  nft -f /etc/nftables.conf
  ;;
lb)
  grep -q ':::80' /etc/haproxy/haproxy.cfg || \
    sed -i 's/^    bind 10.10.10.10:80$/    bind 10.10.10.10:80\n    bind :::80 v6only/' /etc/haproxy/haproxy.cfg
  svc reload haproxy >/dev/null && log "haproxy listening on [::]:80"
  ;;
dns)
  f=/etc/bind/db.dc.lab
  if ! grep -q AAAA $f; then
    cat >> $f <<'EOF'
; IPv6 (dual-stack mode)
lb1     IN AAAA 2001:db8:10:10::10
shop    IN AAAA 2001:db8:10:10::10
web1    IN AAAA 2001:db8:10:10::11
web2    IN AAAA 2001:db8:10:10::12
EOF
    # bump the SOA serial
    python3 -c "import re,sys; p=sys.argv[1]; s=open(p).read(); open(p,'w').write(re.sub(r'(IN SOA[^(]*\\(\\s*)(\\d+)', lambda m: m.group(1)+str(int(m.group(2))+1), s, 1))" $f
    svc reload named >/dev/null && log "AAAA records added"
  fi
  ;;
client)
  grep -q '2001:db8:10:10::10' /etc/hosts || echo "2001:db8:10:10::10 shop.example.com" >> /etc/hosts
  ;;
esac

# ---- 4. default routes for hosts
case ${ROLE:-} in
lb|web|db|dns)
  gw=$(ip -6 -o addr show dev eth1 scope global | awk '{print $4}' | sed -E 's#::[0-9a-f]+/64#::1#')
  [ -n "$gw" ] && ip -6 route replace default via "$gw" && log "default via $gw" ;;
client)
  ip -6 route replace default via 2001:db8:113::1 ;;
esac
touch /run/lab-ipv6

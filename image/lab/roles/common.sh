# Applied to every node before its role script.

# Management (eth0) is out-of-band only: keep the connected /24, drop Docker's default route.
ip route del default dev eth0 2>/dev/null || true

# Use the DC's own DNS server instead of Docker's embedded resolver (127.0.0.11).
if [ "${ROLE:-}" != "client" ]; then
  printf 'search dc.lab\nnameserver 10.10.30.10\noptions timeout:2 attempts:2\n' > /etc/resolv.conf
fi

# Hosts are not routers unless their role says so.
sysctl -qw net.ipv4.ip_forward=0
sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0

mkdir -p /var/log/app /var/log/frr
svc start rsyslog

# SSH listens on the management interface only, like a real out-of-band network.
# Fresh host keys per node (the image ships one set for all of them).
rm -f /etc/ssh/ssh_host_*; ssh-keygen -A >/dev/null
MGMT_IP=$(ip -4 -o addr show dev eth0 | awk '{print $4}' | cut -d/ -f1)
echo "ListenAddress $MGMT_IP" > /etc/ssh/sshd_config.d/listen.conf
svc start sshd

# helper used by the per-node files:  iface <dev> <mtu> [ip/prefix]
iface() {
  ip link set "$1" mtu "$2" up
  [ -n "${3:-}" ] && ip addr add "$3" dev "$1"
  return 0
}

# helper for leaves:  access_vlan <vid> <gateway ip/prefix> <port>...
# Builds a VLAN-aware bridge "br0" with untagged access ports and an SVI "vlan<vid>".
# If the kernel lacks VLAN support (some minimal VM kernels), falls back to one plain
# bridge per VLAN, still named "vlan<vid>" -- same L3 behaviour, no 802.1Q.
access_vlan() {
  local vid=$1 gw=$2; shift 2
  if [ ! -e /run/vlan-mode ]; then
    if ip link add br0 type bridge vlan_filtering 1 2>/dev/null; then
      ip link set br0 up; echo aware > /run/vlan-mode
    else
      echo "[boot] WARNING: kernel has no bridge VLAN filtering; using one bridge per VLAN"
      echo flat > /run/vlan-mode
    fi
  fi
  if [ "$(cat /run/vlan-mode)" = aware ]; then
    for p in "$@"; do
      ip link set "$p" mtu 1500 master br0 up
      bridge vlan del dev "$p" vid 1
      bridge vlan add dev "$p" vid "$vid" pvid untagged
    done
    bridge vlan add dev br0 vid "$vid" self
    ip link add link br0 name "vlan$vid" type vlan id "$vid"
  else
    ip link add "vlan$vid" type bridge
    for p in "$@"; do ip link set "$p" mtu 1500 master "vlan$vid" up; done
  fi
  iface "vlan$vid" 1500 "$gw"
}

# Per-node addressing (interfaces, IPs, MTU, routes)
[ -f "/lab/nodes/$(hostname)/net.sh" ] && source "/lab/nodes/$(hostname)/net.sh"

#!/usr/bin/env bash
# Prepare a Linux host for netchaos-lab: Docker, containerlab, a few tools, kernel modules.
# Run it on Ubuntu/Debian directly, or inside the lab VM on a Mac (scripts/mac-vm.sh runs it for you).
#   ./scripts/setup-host.sh
set -euo pipefail

say()  { printf '\n>> %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*"; }

if [ "$(uname -s)" != Linux ]; then
  echo "This script prepares a Linux host. On a Mac, run scripts/mac-vm.sh instead: it creates" >&2
  echo "a Linux VM (OrbStack or Lima), copies the lab into it and runs this script there." >&2
  exit 1
fi
[ "$(id -u)" -eq 0 ] && { echo "Run this as your normal user (it uses sudo where needed)." >&2; exit 1; }

. /etc/os-release 2>/dev/null || true
case "${ID:-}:${ID_LIKE:-}" in
  ubuntu:*|debian:*|*:*debian*) ;;
  *) warn "tested on Ubuntu and Debian; on ${PRETTY_NAME:-this distro} you may need to install the packages yourself" ;;
esac

say "packages"
sudo apt-get update -qq
sudo apt-get install -y -qq curl ca-certificates git jq iproute2 openssh-client util-linux kmod >/dev/null

if ! command -v docker >/dev/null; then
  say "Docker Engine"
  curl -fsSL https://get.docker.com | sudo sh
fi
if ! id -nG "$(id -un)" | grep -qw docker; then
  sudo usermod -aG docker "$(id -un)"
  NEED_RELOGIN=1
fi

if ! command -v containerlab >/dev/null; then
  say "containerlab"
  bash -c "$(curl -sL https://get.containerlab.dev)"
fi

say "kernel features"
load() {   # load <module> <what it's for>
  if sudo modprobe "$1" 2>/dev/null; then
    echo "   $1: yes ($2)"
    echo "$1" | sudo tee "/etc/modules-load.d/netchaos-$1.conf" >/dev/null
    return 0
  fi
  return 1
}
for m in "sch_netem:latency/loss fault" "8021q:VLAN-aware bridges"; do
  mod=${m%%:*}; what=${m#*:}
  load "$mod" "$what" && continue
  # cloud/stock Ubuntu kernels ship some modules in linux-modules-extra
  if sudo apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 && load "$mod" "$what"; then continue; fi
  case $mod in
    sch_netem) warn "netem not available: that one fault will be skipped" ;;
    8021q)     warn "802.1q not available: leaves fall back to one bridge per VLAN (same behaviour)" ;;
  esac
done
[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && echo "   IPv6: yes (./labctl up --ipv6)" || warn "no IPv6 in this kernel: dual-stack mode unavailable"

say "done"
if [ -n "${NEED_RELOGIN:-}" ]; then
  echo "You were added to the 'docker' group: log out and back in (or run 'newgrp docker'), then:"
else
  echo "Next:"
fi
echo "  ./labctl doctor     # check everything"
echo "  ./labctl up         # first run builds the node image (a few minutes)"

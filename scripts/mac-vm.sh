#!/usr/bin/env bash
# macOS only: create the Linux VM that runs netchaos-lab, copy this checkout into it and prepare it.
#
#   ./scripts/mac-vm.sh               # OrbStack if installed, else Lima
#   ./scripts/mac-vm.sh --lima        # force Lima      (brew install lima)
#   ./scripts/mac-vm.sh --orbstack    # force OrbStack  (brew install orbstack)
#   ./scripts/mac-vm.sh --sync        # copy your latest changes into the existing VM again
#
# Why a copy and not the Mac folder itself: the lab needs real Linux file permissions (the AI
# investigator must NOT be able to read the answers) and a writable disk. VM folder mounts give
# neither reliably: Lima mounts your home read-only, and mounts may ignore chmod. Your journals
# live inside the VM, under ~/netchaos-lab/journal.
set -euo pipefail
VM=netchaos
ENGINE=""; SYNC=""
for a in "$@"; do
  case $a in
    --lima) ENGINE=lima ;; --orbstack) ENGINE=orbstack ;; --sync) SYNC=1 ;;
    --name=*) VM=${a#--name=} ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 1 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo "This is for macOS. On Linux run scripts/setup-host.sh." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)

if [ -z "$ENGINE" ]; then
  if command -v orb >/dev/null; then ENGINE=orbstack
  elif command -v limactl >/dev/null; then ENGINE=lima
  else
    echo "Install OrbStack (brew install orbstack) or Lima (brew install lima) first." >&2; exit 1
  fi
fi

# vmsh <command...>: run a shell command inside the VM as your user
case $ENGINE in
  orbstack)
    command -v orb >/dev/null || { echo "OrbStack not found: brew install orbstack" >&2; exit 1; }
    vmsh() { orb -m "$VM" bash -lc "$1"; }
    exists() { orb list 2>/dev/null | awk '{print $1}' | grep -qx "$VM"; }
    create() { orb create ubuntu "$VM"; }
    SHELL_CMD="orb -m $VM"
    ;;
  lima)
    command -v limactl >/dev/null || { echo "Lima not found: brew install lima" >&2; exit 1; }
    case $REPO in "$HOME"/*) ;; *) echo "With Lima, keep the checkout under your home folder (Lima only mounts ~)." >&2; exit 1 ;; esac
    vmsh() { limactl shell "$VM" bash -lc "$1"; }
    exists() { limactl list -q 2>/dev/null | grep -qx "$VM"; }
    create() { limactl start --name="$VM" --cpus=4 --memory=8 --disk=40 --tty=false template://ubuntu-lts; }
    SHELL_CMD="limactl shell $VM"
    ;;
esac

if exists; then
  echo ">> VM '$VM' exists ($ENGINE)"
else
  [ -n "$SYNC" ] && { echo "VM '$VM' doesn't exist yet - run without --sync first." >&2; exit 1; }
  echo ">> creating VM '$VM' with $ENGINE (Ubuntu)"
  create
fi
# OrbStack/Lima stop VMs when idle or on reboot: make sure it runs
case $ENGINE in orbstack) orb start "$VM" >/dev/null 2>&1 || true ;; lima) limactl start "$VM" >/dev/null 2>&1 || true ;; esac

echo ">> copying $REPO into the VM as ~/netchaos-lab (journals and lab state in the VM are kept)"
vmsh "mkdir -p ~/netchaos-lab && tar -C '$REPO' --exclude=./.state --exclude=./journal --exclude='./clab-*' --exclude=./.git -cf - . | tar -C ~/netchaos-lab -xf -"

if [ -z "$SYNC" ]; then
  echo ">> preparing the VM (Docker, containerlab, tools)"
  vmsh "cd ~/netchaos-lab && ./scripts/setup-host.sh"
fi

cat <<EOF

Done. Open the VM and start the lab:
  $SHELL_CMD
  cd ~/netchaos-lab
  ./labctl doctor
  ./labctl up
After editing files on the Mac, run ./scripts/mac-vm.sh --sync to copy them into the VM again.
EOF

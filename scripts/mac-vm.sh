#!/usr/bin/env bash
# macOS only: create the Linux VM that runs netchaos-lab, copy this checkout into it and prepare it.
#
#   ./scripts/mac-vm.sh               # OrbStack if installed, else Lima
#   ./scripts/mac-vm.sh --lima        # force Lima      (brew install lima)
#   ./scripts/mac-vm.sh --orbstack    # force OrbStack  (brew install orbstack)
#   ./scripts/mac-vm.sh --sync        # copy your latest changes into the existing VM again
#   ./scripts/mac-vm.sh --pull        # copy the VM's journal/ back to this checkout on the Mac
#   ./scripts/mac-vm.sh --name=dclab  # use a VM with another name (default: netchaos)
#   ./scripts/mac-vm.sh --rebuild     # delete the VM and build a fresh one; journals are saved first
#
# Inside the VM, ./labctl keeps ~/netchaos-lab in sync with this checkout by itself (at up, reset
# and break, when no incident is open), so --sync is rarely needed.
#
# The VM name and engine are remembered in .state/mac-vm after the first successful run, so
# later --sync/--pull calls don't need --name or --orbstack/--lima again.
#
# Why a copy and not the Mac folder itself: the lab needs real Linux file permissions (the AI
# investigator must NOT be able to read the answers) and a writable disk. VM folder mounts give
# neither reliably: Lima mounts your home read-only, and mounts may ignore chmod. Your journals
# live inside the VM, under ~/netchaos-lab/journal.
set -euo pipefail
VM=""
ENGINE=""; SYNC=""; PULL=""; REBUILD=""
for a in "$@"; do
  case $a in
    --lima) ENGINE=lima ;; --orbstack) ENGINE=orbstack ;; --sync) SYNC=1 ;; --pull) PULL=1 ;; --rebuild) REBUILD=1 ;;
    --name=*) VM=${a#--name=} ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 1 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo "This is for macOS. On Linux run scripts/setup-host.sh." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
REMEMBER=$REPO/.state/mac-vm          # last VM name/engine used from this checkout
if [ -f "$REMEMBER" ]; then
  saved_vm=$(sed -n 's/^VM=//p' "$REMEMBER"); saved_engine=$(sed -n 's/^ENGINE=//p' "$REMEMBER")
  [ -z "$VM" ] && VM=$saved_vm
  [ -z "$ENGINE" ] && ENGINE=$saved_engine
fi
VM=${VM:-netchaos}

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
    vmraw() { orb -m "$VM" bash -c "$1"; }    # no login shell: clean stdout for piping
    exists() { orb list 2>/dev/null | awk '{print $1}' | grep -qx "$VM"; }
    create() { orb create ubuntu "$VM"; }
    SHELL_CMD="orb -m $VM"
    ;;
  lima)
    command -v limactl >/dev/null || { echo "Lima not found: brew install lima" >&2; exit 1; }
    case $REPO in "$HOME"/*) ;; *) echo "With Lima, keep the checkout under your home folder (Lima only mounts ~)." >&2; exit 1 ;; esac
    vmsh() { limactl shell "$VM" bash -lc "$1"; }
    vmraw() { limactl shell "$VM" bash -c "$1"; }
    exists() { limactl list -q 2>/dev/null | grep -qx "$VM"; }
    create() { limactl start --name="$VM" --cpus=4 --memory=8 --disk=40 --tty=false template://ubuntu-lts; }
    SHELL_CMD="limactl shell $VM"
    ;;
esac

BACKUP=""
if [ -n "$REBUILD" ]; then
  [ -z "$SYNC$PULL" ] || { echo "--rebuild can't be combined with --sync/--pull" >&2; exit 1; }
  exists || { echo "No $ENGINE VM called '$VM' to rebuild (use --name=<vm>)." >&2; exit 1; }
  case $ENGINE in orbstack) orb start "$VM" >/dev/null 2>&1 || true ;; lima) limactl start "$VM" >/dev/null 2>&1 || true ;; esac
  open=""; vmraw "[ -f ~/netchaos-lab/.state/current ]" 2>/dev/null && open=1
  cat <<WARN
!! This DELETES the $ENGINE VM '$VM' and everything inside it: the lab, Docker images, the
!! 'investigator' user and its Claude Code token, and anything else you keep in that VM.
!! Kept: the VM's ~/netchaos-lab/journal, saved first to this checkout as a .tgz, then put back.
WARN
  [ -n "$open" ] && echo "!! An incident is OPEN in the VM. It will be lost (its journal and logs are in the backup)."
  read -rp "Type the VM name ($VM) to confirm: " answer
  [ "$answer" = "$VM" ] || { echo "Not confirmed - nothing changed."; exit 1; }
  BACKUP="$REPO/journal-backup-$VM-$(date +%Y%m%d-%H%M%S).tgz"
  echo ">> saving the VM's journals to $(basename "$BACKUP")"
  vmraw "cd ~/netchaos-lab 2>/dev/null && mkdir -p journal && tar -czf - journal" > "$BACKUP" \
    && tar -tzf "$BACKUP" >/dev/null \
    || { echo "!! journal backup failed - VM NOT deleted ($BACKUP may be incomplete)" >&2; exit 1; }
  echo "   $(tar -tzf "$BACKUP" | grep -c '\.md$') journal files saved"
  # also copy them to ./journal on the Mac, like --pull (keeps files you edited on the Mac)
  mkdir -p "$REPO/journal"
  tar -C "$REPO" --keep-newer-files -xzf "$BACKUP" 2>/dev/null || true
  echo ">> deleting VM '$VM'"
  case $ENGINE in orbstack) orb delete -f "$VM" ;; lima) limactl delete -f "$VM" ;; esac
fi

if exists; then
  echo ">> VM '$VM' exists ($ENGINE)"
else
  if [ -n "$SYNC$PULL" ]; then
    case $ENGINE in
      orbstack) vms=$(orb list 2>/dev/null | awk '{print $1}' | grep -v '^NAME$' | tr '\n' ' ') ;;
      lima)     vms=$(limactl list -q 2>/dev/null | tr '\n' ' ') ;;
    esac
    echo "No $ENGINE VM called '$VM'. Your $ENGINE VMs: ${vms:-none}" >&2
    echo "If the lab lives in one of them, say which once (it's remembered): $0 --name=<vm> ${SYNC:+--sync}${PULL:+--pull}" >&2
    echo "To create the '$VM' VM instead, run without --sync/--pull." >&2
    exit 1
  fi
  echo ">> creating VM '$VM' with $ENGINE (Ubuntu)"
  create
fi
mkdir -p "$REPO/.state" && printf 'VM=%s\nENGINE=%s\n' "$VM" "$ENGINE" > "$REMEMBER"
# OrbStack/Lima stop VMs when idle or on reboot: make sure it runs
case $ENGINE in orbstack) orb start "$VM" >/dev/null 2>&1 || true ;; lima) limactl start "$VM" >/dev/null 2>&1 || true ;; esac

if [ -n "$SYNC" ] && vmraw "[ -f ~/netchaos-lab/.state/current ]" 2>/dev/null; then
  echo "An incident is open in the VM: finish it (./labctl check or reveal) before syncing code." >&2
  echo "Changing faults/ or labctl in the middle of an incident can break it." >&2
  exit 1
fi

if [ -n "$PULL" ]; then
  # Journals are written inside the VM (labctl, the AI investigator). Copy them out so you can read
  # them, edit them and run the postmortem jury on the Mac. Files you edited on the Mac after the
  # last pull are newer than the VM's copy and are kept (--keep-newer-files).
  mkdir -p "$REPO/journal"
  # files only (no directory entries): tar would complain that the Mac's journal/ dir is "newer"
  vmraw "cd ~/netchaos-lab/journal 2>/dev/null && find . -type f -print0 | tar --null -T - -cf -" \
    | tar -C "$REPO/journal" --keep-newer-files -xf - 2>&1 | grep -v 'is newer\|Error exit delayed\|Exiting with failure' || true
  echo ">> journals copied to $REPO/journal ($(find "$REPO/journal" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ') .md files)"
  exit 0
fi

echo ">> copying $REPO into the VM as ~/netchaos-lab (journals and lab state in the VM are kept)"
vmsh "mkdir -p ~/netchaos-lab && tar -C '$REPO' --exclude=./.state --exclude=./journal --exclude='./clab-*' --exclude=./.git -cf - . | tar -C ~/netchaos-lab -xf -"
# tell labctl in the VM where its source is, so it can keep itself in sync (labctl sync)
vmsh "mkdir -p ~/netchaos-lab/.state && printf '%s\n' '$REPO' > ~/netchaos-lab/.state/source && touch ~/netchaos-lab/.state/synced-at"
if [ -n "$BACKUP" ]; then
  echo ">> restoring the journals into the new VM"
  vmraw "tar -C ~/netchaos-lab -xzf -" < "$BACKUP"
fi

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
labctl in the VM picks up your edits on the Mac by itself (at up, reset and break).${BACKUP:+
Then set up the AI investigator again:  sudo ./ai/setup-ai.sh --token}
EOF

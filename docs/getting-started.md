# Getting started

netchaos-lab runs on **Linux**: containerlab needs a Linux kernel it fully controls (network
namespaces, veth pairs, bridges). On a Mac, the lab runs in a small Linux VM, and a script sets that
up for you.

| | Ubuntu / Debian | macOS (Apple Silicon or Intel) |
|---|---|---|
| Where the lab runs | directly on the machine | in a Linux VM created by OrbStack or Lima |
| Setup | `./scripts/setup-host.sh` | `./scripts/mac-vm.sh` |
| Resources | ~3 GB free RAM, 2+ CPUs, ~3 GB disk | the VM gets 4 CPUs, 8 GB RAM, 40 GB disk (Lima; OrbStack shares dynamically) |

## Ubuntu / Debian

Tested on Ubuntu 24.04. Debian 12 and other recent Ubuntu releases should work.

```bash
git clone https://github.com/marion-official/netchaos-lab.git
cd netchaos-lab
./scripts/setup-host.sh      # Docker, containerlab, tools, kernel modules (uses sudo)
# log out and back in if it added you to the docker group
./labctl doctor              # everything green? (yellow = optional feature missing)
./labctl up                  # first run builds the node image: a few minutes
```

Everything else ([playing](playing.md), the [cheat sheet](nodes-cheatsheet.md)) happens in that
folder.

`setup-host.sh` is safe to re-run. It installs Docker with Docker's official script and
containerlab with its official installer, both only if missing. It also loads `sch_netem` and
`8021q` if the kernel has them (installing `linux-modules-extra` on stock Ubuntu kernels when
needed). The lab works without either module: the one netem fault is skipped, and VLANs fall back
to one bridge per VLAN.

## macOS

Install one VM tool first:

- **OrbStack** (`brew install orbstack`) is the easiest and lightest. It's free for personal use;
  check its licence for commercial use.
- **Lima** (`brew install lima`) is fully open source.

Then, from your clone on the Mac:

```bash
git clone https://github.com/marion-official/netchaos-lab.git
cd netchaos-lab
./scripts/mac-vm.sh          # OrbStack if installed, else Lima (--lima / --orbstack to choose)
```

The script creates an Ubuntu VM named `netchaos`, copies the checkout into it as `~/netchaos-lab`,
and runs `setup-host.sh` there. Then:

```bash
orb -m netchaos              # OrbStack    (Lima: limactl shell netchaos)
cd ~/netchaos-lab
./labctl doctor
./labctl up
```

**Why a copy inside the VM, and not your Mac folder?** The lab needs real Linux file permissions:
the [AI investigator](ai-investigator.md) must not be able to read the answers. It also needs a
writable disk. VM folder mounts don't reliably give you either: Lima mounts your home read-only,
and mounts can ignore `chmod`. Your journals therefore live in the VM, under
`~/netchaos-lab/journal`.

- **To pick up changes made on the Mac:** run `./scripts/mac-vm.sh --sync`. It copies the files
  again; journals and lab state in the VM are kept.
- **Apple Silicon** works natively: the node image is built locally for arm64.

## After a reboot

The lab's virtual cables don't survive a reboot of the host or the VM. If an incident was open,
run `./labctl recover` (it keeps the incident). Otherwise run `./labctl reset`. Details:
[playing](playing.md#after-a-reboot-mac-vm-or-linux-host).

## Uninstall

```bash
./labctl down                      # remove the lab containers
docker image rm netchaos/node      # remove the node image
# on a Mac, remove the VM:  orb delete netchaos   |   limactl delete -f netchaos
```

`labctl up` adds `Include ~/.ssh/netchaos.conf` to `~/.ssh/config` and creates a lab-only key
`~/.ssh/netchaos_ed25519`. Delete those if you want to remove all traces.

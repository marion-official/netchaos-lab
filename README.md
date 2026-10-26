# netchaos-lab

**A small, realistic datacenter in containers that breaks on purpose, so you can practise fixing it.**

[![CI](https://github.com/marion-official/netchaos-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/marion-official/netchaos-lab/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)

A chaos script injects a fault somewhere between the internet and the database. You get a ticket
that describes the **symptom, never the cause**. Then you troubleshoot it with the tools you'd use
on real servers: `ping`, `tcpdump`, `ip`, `ss`, `dig`, `vtysh`, `nft`, `curl`, logs.

```
$ ./labctl break --level 2

🎫 TICKET  (level 2)

   shop.example.com returns errors (HTTP 503) for ALL customers.
   Nobody has touched the web servers today.

$ ssh web1 'tail -3 /var/log/app/app.log'
...
$ ./labctl check
✔ customer view (IPv4): homepage 20/20 OK, avg 0.01s; /report HTTP 200 (1605000 bytes)
🎉 RESOLVED in 14 min with 1 hint(s).
```

It's built for people who want to get better at troubleshooting networks and Linux services:
students, sysadmins, SREs, and anyone curious how well an AI agent troubleshoots compared with a
human.

## Features

- **A real topology:**
  - a BGP spine-leaf fabric with ECMP;
  - VLANs on Linux bridges;
  - an nftables edge firewall with NAT;
  - HAProxy in front of nginx and a Python app, with PostgreSQL and BIND behind them;
  - an out-of-band management network;
  - optional IPv6 dual-stack.
- **29 faults** (25 IPv4 + 4 IPv6-only) across L1-L7, in three difficulty levels: ports, VLANs, ARP and MAC learning,
  routing, BGP, longest-prefix match, MTU/PMTUD, TTL, reverse-path filtering, firewalls, NAT, DNS,
  load balancer, database auth, bad deploys, duplicate addresses, and IPv6-only failures.
  Parameters are randomised, so a fault plays differently each time.
- **Honest checking:** `labctl check` passes only when customers are happy *and* the root cause is
  gone. Restarting things until the symptom disappears doesn't count.
- **Evidence of how you worked:**
  - every command you type on any node is logged (with exit codes), however you got in;
  - session output is recorded;
  - a journal template walks you through the 7 troubleshooting steps and a postmortem.
- **A postmortem jury:** a Claude skill reviews a finished incident against the sealed ground truth.
  It scores root-cause accuracy, causal depth, hypothesis and evidence quality, false leads, risky
  changes and the remedy, and shows the shortest expert path.
- **A human-vs-AI experiment kit:** Claude Code as an isolated investigator, with the same access as
  you and none to the answers. Its commands are tagged, and its reasoning is saved for the jury.

## Quick start

**Ubuntu / Debian**

```bash
git clone https://github.com/<you>/netchaos-lab.git && cd netchaos-lab
./scripts/setup-host.sh       # Docker + containerlab + tools (log out/in afterwards if asked)
./labctl doctor && ./labctl up
./labctl break --level 1
```

**macOS** (with [OrbStack](https://orbstack.dev) or [Lima](https://lima-vm.io))

```bash
git clone https://github.com/<you>/netchaos-lab.git && cd netchaos-lab
./scripts/mac-vm.sh           # creates an Ubuntu VM, copies the lab into it, sets it up
orb -m netchaos               # or: limactl shell netchaos
cd ~/netchaos-lab && ./labctl up && ./labctl break --level 1
```

Full instructions: [docs/getting-started.md](docs/getting-started.md).

## The datacenter

```
 inet-client ── fw ── border ──┬── spine1 ──┬── leaf1 ── lb1 (HAProxy), web1, web2 (nginx + app)
 "the internet"  NAT   BGP     └── spine2 ──┴── leaf2 ── db1 (PostgreSQL), dns1 (BIND)
                                eBGP + ECMP            VLANs on Linux bridges
```

A customer request crosses the whole stack, so almost any fault shows up as a customer-visible
symptom, as in a real datacenter. Details: [docs/architecture.md](docs/architecture.md).

## Playing

```bash
./labctl break --level 1|2|3       # inject a random fault, show the ticket
ssh web1                           # reach any node (or ./labctl shell web1 to record the output)
./labctl status                    # what customers see
./labctl hint                      # three hints per fault, vague to specific
./labctl check                     # done?
./labctl reveal                    # give up: root cause, how to see it, the fix, the lesson
```

More: [playing](docs/playing.md) · [node cheat sheet](docs/nodes-cheatsheet.md) (no systemd on the
nodes: `svc`, logs, HAProxy) · [IPv6 mode](docs/ipv6.md).

## Journal, command log and the jury

Every incident creates `journal/<timestamp>.md`, a 7-step template ending in a postmortem: causal
chain, remedy, detection, prevention. Your commands land next to it. When you finish, Claude Code
in this repo can run the **postmortem jury** (`.claude/skills/postmortem-jury`) on it.
See [docs/journal-and-jury.md](docs/journal-and-jury.md).

## Human vs AI

`ai/` sets up Claude Code as an investigator under its own Linux user. File permissions and a single
sudo rule keep it away from the answers, and hooks record everything. There are four conditions:

- human
- AI (baseline)
- AI with a troubleshooting-method skill
- human with AI as copilot

Run the same fault and seed under each condition and compare the jury's scores.
See [docs/ai-investigator.md](docs/ai-investigator.md).

## Spoilers

`faults/` contains every fault *and its solution*. Don't read it while you practise. The open
incident's state is base64-encoded against accidental `cat`s. This is an honor system, not
security; only the AI investigator is locked out for real.

## Documentation

| | |
|---|---|
| [Getting started](docs/getting-started.md) | Ubuntu and macOS setup, reboots, uninstall |
| [Playing](docs/playing.md) | commands, reaching nodes, recovering after a reboot |
| [Node cheat sheet](docs/nodes-cheatsheet.md) | `svc` instead of systemd, log locations, HAProxy runtime API |
| [IPv6 dual-stack](docs/ipv6.md) | the addressing plan and IPv6-only faults |
| [Journal and jury](docs/journal-and-jury.md) | the 7 steps, the command log, the postmortem jury |
| [AI investigator](docs/ai-investigator.md) | isolation, hooks, experiment conditions |
| [Architecture](docs/architecture.md) | topology, how a fault runs, design choices, limits |
| [Writing faults](docs/writing-faults.md) | the fault contract and helpers, plus how to test |

## Status

`0.1.0`, early but complete.

- **Ubuntu:** CI deploys the lab with containerlab on GitHub's Ubuntu runners and injects and fixes
  every fault on each push.
- **macOS:** the VM setup is untested by CI, so reports from Mac users are very welcome.

`./labctl doctor` prints what an issue report needs.

## Contributing

New faults are the most valuable contribution. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/writing-faults.md](docs/writing-faults.md).

## License

[MIT](LICENSE)

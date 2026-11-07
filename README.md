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
git clone https://github.com/marion-official/netchaos-lab.git && cd netchaos-lab
./scripts/setup-host.sh       # Docker + containerlab + tools (log out/in afterwards if asked)
./labctl doctor && ./labctl up
./labctl break --level 1
```

**macOS** (with [OrbStack](https://orbstack.dev) or [Lima](https://lima-vm.io))

```bash
git clone https://github.com/marion-official/netchaos-lab.git && cd netchaos-lab
./scripts/mac-vm.sh           # creates an Ubuntu VM, copies the lab into it, sets it up
orb -m netchaos               # or: limactl shell netchaos
cd ~/netchaos-lab && ./labctl up && ./labctl break --level 1
# edit on the Mac, run in the VM: labctl syncs your Mac edits in by itself (at up/reset/break)
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
./labctl faults                    # spoiler-free list: which faults you've solved (add --unsolved to break)
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

### Judging an incident with Claude Code outside the VM (Mac)

On a Mac, the lab and its journals live **inside the VM** (`~/netchaos-lab/journal`), while you
probably run Claude Code on the Mac. `--sync` only copies Mac → VM and never touches `journal/`, so
copy the journals out first:

1. **Close the incident** in the VM: `./labctl check` passes, or `./labctl reveal`. This seals
   the ground truth (`<ts>.solution.md`) and writes the final command log. For an AI run, make sure
   the AI session ended with `/exit`, so its transcript is saved.
2. **Copy the journals to the Mac.** On the Mac, from your checkout:
   ```bash
   ./scripts/mac-vm.sh --pull                 # first time: add --name=<vm> if your VM isn't "netchaos" (remembered)
   ```
   Or, from inside an OrbStack VM, where the Mac folder is mounted read-write:
   ```bash
   cp -a ~/netchaos-lab/journal/. /Users/<you>/path/to/netchaos-lab/journal/
   ```
   Either way you get every journal, command log, recording, AI transcript and sealed solution.
   `--pull` keeps files you've edited on the Mac since the last pull; `cp` overwrites them.
3. **Run the jury** in the Mac checkout:
   ```bash
   cd netchaos-lab && claude
   > run the postmortem jury on my last incident      # or name a journal: journal/20261103-154745.md
   ```
   The review is written to `journal/<ts>.review.md`, on the Mac. `--sync` skips `journal/`, so
   copy the review into the VM by hand if you want it there too.

Running the jury inside the VM works too, as your own user in `~/netchaos-lab`. Never as
`investigator`: it can't read the journals, by design.

## Human vs AI

`ai/` sets up Claude Code as an investigator under its own Linux user. File permissions and a single
sudo rule keep it away from the answers, and hooks record everything. There are four conditions:

- human
- AI (baseline)
- AI with a troubleshooting-method skill
- human with AI as copilot

Run the same fault and seed under each condition and compare the jury's scores.

**One AI run, start to finish** (on the lab host: the VM on a Mac):

```bash
# your shell, in ~/netchaos-lab
sudo ./ai/setup-ai.sh                     # before EVERY run: fresh workspaces, wiped AI memory
./labctl break --fault ID --seed N --investigator ai+method     # or: ai (no method skill)

# a second terminal: become the investigator
sudo -iu investigator
cd ~/ws-method && claude --dangerously-skip-permissions          # ws-baseline for "ai"
```

The first time, Claude asks you to log in. If you can't copy the login URL out of the VM terminal,
create a token on your Mac with `claude setup-token` and store it with `sudo ./ai/setup-ai.sh --token`.

Paste this prompt, word for word, then keep your hands off:

> There is an open incident. Investigate it, resolve it, verify with `lab check`, and write the journal.

If it stops to ask you something, always answer the same way, and note the intervention in the
journal: *"You're the on-call engineer. Decide yourself and continue."* End with `/exit`: that's
what saves the transcript. On a Mac, `./scripts/mac-vm.sh --pull` brings everything out.

Details, the first-time login and a dry-run checklist: [docs/ai-investigator.md](docs/ai-investigator.md).

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

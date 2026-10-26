# Changelog

## 0.1.0 - 2026-10-25

First public release.

- A 12-node containerlab datacenter: eBGP spine-leaf with ECMP, VLAN bridges, an nftables edge
  firewall with NAT, HAProxy, nginx + Python app, PostgreSQL, BIND, an out-of-band management network.
- `labctl` with 29 faults (25 IPv4 + 4 IPv6) in three levels, plus tickets, hints, `check`
  (symptom gone and root cause removed), `reveal`, `recover` after reboots, and `doctor`.
- Optional IPv6 dual-stack mode.
- Evidence: per-incident journal (7 steps + postmortem), a complete command log across every way
  of reaching a node, session recordings, sealed ground truth.
- Postmortem jury Claude skill.
- AI investigator: an isolated Claude Code user, a restricted `lab` wrapper, hooks, and baseline and
  method workspaces.
- Host setup for Ubuntu/Debian, plus macOS through OrbStack or Lima.

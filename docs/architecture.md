# Architecture

## The datacenter

```
 inet-client 203.0.113.100      "the internet" (a customer)
      |
     fw   nftables: stateful filter, DNAT 203.0.113.10:80 -> lb1, SNAT outbound
      |  10.0.9.0/31
    border                                   AS 65103, originates the default route
     /    \
 spine1   spine2                             AS 65000, eBGP on /31 point-to-points, ECMP
     \  /  \  /
   leaf1    leaf2                            AS 65101 / 65102, Linux bridge + SVIs (the rack switches)
     |        |
  VLAN 10   VLAN 20 10.10.20.0/24: db1   (PostgreSQL 15 + host firewall)
  10.10.10.0/24  VLAN 30 10.10.30.0/24: dns1  (BIND9, authoritative for dc.lab)
  lb1  (HAProxy, 10.10.10.10)
  web1 (nginx -> python app, 10.10.10.11)
  web2 (nginx -> python app, 10.10.10.12)

 + out-of-band management network 172.30.30.0/24 on eth0 of every node (not routed, no default route)
```

A request travels: customer -> fw (DNAT) -> border -> spine (ECMP) -> leaf1 -> lb1 -> web1/web2 ->
DNS lookup of `db1.dc.lab` on dns1 -> PostgreSQL on db1. So a fault at almost any layer shows up
as a customer-visible symptom, like in a real DC.

Fabric links use MTU 9000, server ports use 1500. ECMP hashes on L4 (per flow), so a fault on
one spine gives *intermittent* failures, as it would in a real fabric.

Every node runs the same Debian image with a full debugging toolbox. There's no systemd: see the
[nodes cheat sheet](nodes-cheatsheet.md).

## How it works

| Piece | What it does |
|---|---|
| `topology.clab.yml` | containerlab topology: 12 nodes, the links between them, management IPs, and each node's role |
| `image/` | one Debian image for every node (the "golden image"): FRR, nftables, HAProxy, nginx, BIND, PostgreSQL, a debugging toolbox |
| `image/lab/entrypoint.sh` + `roles/` + `nodes/<name>/` | at boot, each node waits for its links, applies its addresses (`net.sh`), then starts its role's services |
| `labctl` | the CLI: deploys the lab, injects faults, checks fixes, keeps the incident state in `.state/` and the evidence in `journal/` |
| `faults/` | one Bash file per fault: pick parameters, write the ticket, inject, verify, fix, hints, solution. See [writing faults](writing-faults.md) |
| `audit/node-setup.sh` | pushed into every node at `up`/`break`: logs every interactive command, wraps sshd to log `ssh node cmd`, sets up a usable `vi` |
| `ipv6/node-setup.sh` | dual-stack mode: derives IPv6 addresses, BGP sessions and firewall rules from the IPv4 plan |
| `ai/` | the AI investigator: isolated user setup, the restricted `lab` wrapper, Claude Code workspaces with hooks, the method skill |
| `.claude/skills/postmortem-jury/` | the Claude skill that reviews a finished incident |

**One incident, start to finish:**

1. `labctl break` picks a fault, randomises its parameters (which server, which port, which value)
   and runs its `fault_inject` on the nodes. The parameters are saved in `.state/current`.
2. The ticket describes only symptoms. `labctl status` shows the customer's view: page loads and a
   large download from `inet-client`.
3. While you work, nodes log your commands, and a `docker events` recorder logs `docker exec`
   one-offs. labctl's own commands carry a marker and are filtered out.
4. `labctl check` passes only when the customer view is healthy **and** the fault's `fault_verify`
   says the root cause is gone **and** the internal checks pass (BGP, HAProxy backends, DNS).
5. At `check` or `reveal`, labctl seals the ground truth (`<ts>.solution.md`) and the merged command
   log next to the journal.

**Why one image for all nodes?** It builds once (natively on arm64 and amd64), and every node has
the same tools, the way a fleet built from one golden image would.

**Why containerlab rather than plain Docker networks?** Docker networks are bridges that Docker
manages: its own iptables rules, an embedded DNS server, and no point-to-point links. containerlab
gives real veth "cables" between nodes, so the leaves are bridges you control and the routers really
route.

## Known limits (Docker isn't hardware)

- All containers share the host's kernel. Clock skew, kernel panics and real NIC errors can't be
  simulated honestly, so they're left out.
- "Cables" are veth pairs, so there's no CRC error, autonegotiation or duplex mismatch. Degraded
  links are simulated with `tc netem`.
- Routers are Linux + FRR, not a vendor OS. The concepts carry over, the CLI syntax only partly.

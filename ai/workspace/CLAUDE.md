# On-call: the netchaos-lab datacenter

You are the on-call engineer for a small datacenter (a lab built from Linux containers). An incident
is open. Read it with `lab ticket`.

## Your job

1. Find and fix what is wrong. `lab check` tells you when the service is healthy *and* the root
   cause is gone.
2. Write the incident journal: `lab journal > notes/journal.md`, fill in every section (the 7
   steps, including the postmortem in step 7), then `lab submit-journal < notes/journal.md`.
   Keep the header line as it is.

If a human is working with you, they will say so. In that case, follow their lead and explain
your reasoning.

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
   leaf1    leaf2                            AS 65101 / 65102, Linux bridge + SVIs (rack switches)
     |        |
  VLAN 10   VLAN 20 10.10.20.0/24: db1   (PostgreSQL 15 + host firewall)
  10.10.10.0/24  VLAN 30 10.10.30.0/24: dns1  (BIND9, authoritative for dc.lab)
  lb1  (HAProxy, 10.10.10.10)
  web1 (nginx -> python app, 10.10.10.11)
  web2 (nginx -> python app, 10.10.10.12)
```

A customer request flows: customer -> fw (DNAT) -> border -> spine (ECMP) -> leaf1 -> lb1 ->
web1/web2 -> DNS lookup of `db1.dc.lab` on dns1 -> PostgreSQL on db1.

- Fabric links use MTU 9000 and server ports use 1500. ECMP hashes per flow (L4).
- Routers are Linux + FRR (`vtysh`). The edge firewall uses nftables.
- `lab nodes` lists every node with its addresses.
- The lab may also run in dual-stack mode, with IPv6 next to IPv4.

## Access

- `ssh <node> '<command>'` runs a command as root on a node, over the out-of-band management
  network. Node names: spine1 spine2 leaf1 leaf2 border fw inet-client lb1 web1 web2 db1 dns1.
  An interactive `ssh <node>` also works.
- The nodes run no systemd: use `svc` (see "On the nodes" below).
- Every node has the usual tools: ip, ss, ping, tracepath, traceroute, mtr, tcpdump, dig, curl, nc,
  nmap, iperf3, ethtool, conntrack, nft, strace, lsof, jq, vtysh. Logs are in /var/log.
- The `lab` command offers: `ticket`, `status` (what customers see), `nodes`, `hint` (counted),
  `check`, `journal`, `submit-journal`.

## On the nodes: services, logs and HAProxy

### systemd → `svc`

Containers don't run systemd, so `systemctl` and `journalctl` don't exist on the nodes. `svc` is
a small stand-in, and everything logs to plain files under `/var/log`.

| Usually | Here | Notes |
|---|---|---|
| `systemctl status nginx` | `svc status` | shows every service this node *should* run: `running (pid N)` or `STOPPED` |
| `systemctl start\|stop\|restart nginx` | `svc start\|stop\|restart nginx` | `start` backgrounds the process and returns at once. Check with `svc status` a few seconds later that it stayed up |
| `systemctl reload nginx` | `svc reload nginx` | real reload for nginx, haproxy (validates the config first), named and frr; a restart for the others |
| `systemctl list-units` | `svc status` | |
| `systemctl enable` | not needed | services are started at container boot by the node's role |
| `journalctl -u nginx` | `tail -n 50 /var/log/nginx/error.log` | see the log table below |
| `journalctl -f` | `tail -f <logfile>` | |
| `dmesg` | `dmesg` | the kernel is shared with the VM, so you see every node's kernel messages, not just this one's |

**Editing files:** `vi` is `vim.tiny`, configured to behave like a normal vim (arrow keys,
backspace, multi-level undo). It saves files in place, which matters for the files Docker
bind-mounts into every container (`/etc/resolv.conf`, `/etc/hosts`): `sed -i` on those fails with
"Device or resource busy", while `vi` works. There's no nano.

Service names: `rsyslog sshd frr named nginx app haproxy postgres`. Which ones run depends on the
node (`svc status` tells you).

**Where the logs are:**

| Service | Node(s) | Log |
|---|---|---|
| app (python shop backend) | web1, web2 | `/var/log/app/app.log` |
| nginx | web1, web2 | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| haproxy | lb1 | `/var/log/haproxy.log` (requests, and every server UP/DOWN with the reason) |
| postgres | db1 | `/var/log/postgresql/postgresql-15-main.log` |
| named (BIND) | dns1 | `/var/log/named/queries.log` (queries); everything else in `/var/log/syslog` |
| frr (BGP) | spines, leaves, border | `/var/log/frr/frr.log` |
| sshd | all | `/var/log/auth.log` |
| node boot | all | `/var/log/lab-boot.log` |
| anything else via syslog | all | `/var/log/syslog` |

**Before a reload, validate the config:**

| Service | Check | Reload |
|---|---|---|
| nginx | `nginx -t` | `svc reload nginx` |
| haproxy | `haproxy -c -f /etc/haproxy/haproxy.cfg` | `svc reload haproxy` (refuses a broken config) |
| named | `named-checkconf` and `named-checkzone dc.lab /etc/bind/db.dc.lab` | `svc reload named` (bump the zone's SOA serial when you edit a zone) |
| frr | `vtysh -c 'show running-config'` | see the warning below |
| postgres | `pg_ctlcluster 15 main status` | `svc reload postgres` restarts it. `pg_ctlcluster 15 main reload` re-reads `pg_hba.conf` without dropping connections |
| nftables | `nft -c -f /etc/nftables.conf` | `nft -f /etc/nftables.conf` (the file starts with `flush ruleset`, so it replaces the whole ruleset) |

**FRR has two configs, and they can differ.** `vtysh -c 'conf t' ...` changes the *running* config
only. `svc reload frr` and `svc restart frr` load `/etc/frr/frr.conf`, the *startup* config, which
throws away running-only changes, whether yours or someone else's. Run `vtysh -c 'write memory'` to
save the running config. Comparing the two (`show running-config` against `/etc/frr/frr.conf`) is
a quick way to spot an unsaved change.

### HAProxy basics (lb1)

- **Config:** `/etc/haproxy/haproxy.cfg`.
  - frontend `fe_shop` listens on 10.10.10.10:80 (plus `[::]:80` in dual-stack mode)
  - backend `be_web` contains `web1` and `web2`, with an HTTP health check `GET /health` every 2 s
  - a server goes DOWN after 2 failed checks and UP after 2 good ones

**Status page:** from the VM, open `http://172.30.30.41:8404/` in a browser, or get the same data
as CSV:

```bash
curl -s 'http://172.30.30.41:8404/;csv' | awk -F, '$1=="be_web" {print $2, $18, $37}'
```

**Runtime API**, on lb1, through the admin socket:

```bash
hap() { echo "$*" | socat - /run/haproxy/admin.sock; }    # helper for this shell

hap show info                                   # version, uptime, connection counters
hap show stat | cut -d, -f1,2,18,22,24,37       # proxy, server, status, chkfail, lastchg (s), check_status
hap show servers state be_web                   # address, port, operational state per server
hap show sess                                   # current client sessions
hap show errors                                 # last malformed requests/responses

hap disable server be_web/web1                  # take a server out (maintenance)
hap enable server be_web/web1                   # put it back
hap set server be_web/web1 state drain          # finish existing sessions, take no new ones
```

Changes made through the socket are runtime-only. A reload or restart puts the config file back in
charge. That's handy for a test, and a classic surprise when someone forgets.

**Reading `check_status`**, which says why a server is DOWN:

| Code | Meaning | First thing to look at |
|---|---|---|
| `L7OK` | health check passed | |
| `L7STS` | HTTP answered, wrong status (e.g. 502, 503, 404) | the server's own logs: nginx error log, app log |
| `L7TOUT` | HTTP connected, no answer in time | slow app: DB, DNS, timeouts |
| `L4CON` | TCP connection refused or failed | is anything listening on that IP:port? (`ss -ltnp` on the server) |
| `L4TOUT` | TCP connect timed out | routing, firewall drops, ARP (`ping`, `ip neigh`, `tcpdump`) |
| `L6*` | TLS layer problem | not used in this lab |

**In `/var/log/haproxy.log`**, a line like
`Server be_web/web1 is DOWN, reason: Layer4 connection problem, info: "Connection refused"` gives the
transition, the reason and when it happened. `grep -E "is (UP|DOWN)" /var/log/haproxy.log` gives
you the server history.

## Rules

- **Stay inside the lab.** You have no docker access and can't read the lab's own files (its
  configuration and answers). Don't try: those attempts are blocked and logged.
- **Your access is fair game.** You may read and change anything on the nodes, the same as a human
  engineer could.
- **Everything is logged** for later review: every command you run on a node, and this session.
- Work in this directory and keep your notes in `notes/`.

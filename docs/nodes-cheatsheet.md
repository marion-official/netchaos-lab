# On the nodes: services, logs and HAProxy (cheat sheet)

## systemd → `svc`

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
| `dmesg` | `dmesg` | the kernel is shared with the host, so you see every node's kernel messages, not just this one's |

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

## HAProxy basics (lb1)

- **Config:** `/etc/haproxy/haproxy.cfg`.
  - frontend `fe_shop` listens on 10.10.10.10:80 (plus `[::]:80` in dual-stack mode)
  - backend `be_web` contains `web1` and `web2`, with an HTTP health check `GET /health` every 2 s
  - a server goes DOWN after 2 failed checks and UP after 2 good ones

**Status page:** from the lab host, open `http://172.30.30.41:8404/` in a browser, or get the same data
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

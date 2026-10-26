# Writing a fault

> Spoiler warning: this page explains how faults work, using a toy example. It doesn't describe
> any of the shipped faults, but reading `faults/` does.

Each fault is one Bash file in `faults/`, named `l<level>-<short-name>.sh`. `labctl` sources it and
calls its functions. The file name (without `.sh`) is the fault id.

## The contract

| Name | Required | Purpose |
|---|---|---|
| `FAULT_LEVEL=1\|2\|3` | yes | difficulty. Must match the `l<level>` prefix of the file name |
| `FAULT_LAYER="..."` | yes | short description, shown only in solutions and maintainer output |
| `fault_pick` | yes | choose random parameters, stored in variables named `P_*` (they're saved with the incident) |
| `fault_ticket` | yes | the ticket: **symptoms only**, as a user or monitoring system would report them. A change-log hint ("a template was rolled out") is fine, the cause is not |
| `fault_inject` | yes | break the lab, using the `P_*` parameters |
| `fault_verify` | yes | exit 0 when the **root cause is gone**. It's combined with the customer view and the internal checks to decide `check` |
| `fault_fix` | yes | the reference fix. Used by `selftest-faults`, never shown to players |
| `fault_hints` | yes | exactly three lines, from vague to specific. Hints point at *where to look and with what tool*, not at the answer |
| `fault_solution` | yes | root cause, how to see it (commands and the output to expect), the fix, and the lesson |
| `fault_supported` | no | return non-zero when the fault can't run here, e.g. `fault_supported() { ipv6_on; }` for IPv6-only faults, or a kernel feature check |
| `fault_refresh` | no | re-read runtime details that change when the lab is redeployed by `labctl recover` (MAC addresses, for example) |

## Helpers available to fault files

| Helper | Does |
|---|---|
| `x <node> '<cmd>'` | run a shell command as root on a node (it's marked, so it's excluded from the command audit) |
| `pick a b c` | random choice (reproducible with `labctl break --seed N`) |
| `ip_of`, `leaf_of`, `port_of`, `vlan_of <server>` | topology facts for the servers |
| `ticket_by_target <node>` | standard symptom text depending on which server is affected |
| `say <text>` | print a line (use in `fault_ticket`) |
| `ipv6_on` | true in dual-stack mode |

## A toy example

```bash
# faults/l1-example-nginx-stopped.sh
FAULT_LEVEL=1
FAULT_LAYER="L7 web server"
fault_pick()   { P_T=$(pick web1 web2); }
fault_ticket() { ticket_by_target "$P_T"; }
fault_inject() { x $P_T "nginx -s quit"; }
fault_verify() { x $P_T "curl -sf -m 3 http://127.0.0.1/health"; }
fault_fix()    { x $P_T "svc start nginx"; }
fault_hints() {
  echo "Which backend does HAProxy mark DOWN, and with which check_status?"
  echo "On that server: what listens on port 80? (ss -ltnp)"
  echo "svc status on $P_T"
}
fault_solution() { cat <<EOT
ROOT CAUSE: nginx is stopped on $P_T. HAProxy's health check gets "connection refused" (L4CON).
Fix: svc start nginx
Lesson: L4CON means nothing listens on that port; look at the process before the network.
EOT
}
```

## Rules that keep faults good

- **Realistic causes.** Model something that happens in production: a typo, a bad deploy, a leftover
  test change, two harmless changes that interact. Avoid "random breakage".
- **Restart-proof where it matters.** If restarting a service would "fix" the symptom while the
  cause stays, `fault_verify` must check the cause, not just the symptom.
- **Accept any valid fix.** `fault_verify` checks the state (the route is right, the port is owned
  by the app, the rule allows the traffic). It doesn't check that the player typed the reference
  command.
- **Don't leak the answer.** No hints in the ticket beyond what users and change logs would say.
  Injected processes and files should look like what a human would have left behind.
- **`pkill -f`/`pgrep -f` inside `x`:** the pattern also matches the `bash -c` command line that
  carries it, so `pkill` kills its own shell. Use a bracket, e.g. `pkill -f '[/]lab/app/app.py'`.
- **Files Docker bind-mounts** (`/etc/resolv.conf`, `/etc/hosts`) can't be replaced: `sed -i`
  fails with "Device or resource busy". Rewrite them in place: `r=$(sed ... file) && echo "$r" > file`.

## Test it

```bash
./labctl selftest-faults l1-example-nginx-stopped     # inject -> must break -> fix -> must recover
./labctl selftest-faults l1-example-nginx-stopped l1-example-nginx-stopped   # random parameters differ per run
```

`selftest-faults` passes only if the fault visibly breaks something (the customer view, internal
checks or `fault_verify`), and the reference fix brings everything back. CI runs it for every fault
on every pull request.

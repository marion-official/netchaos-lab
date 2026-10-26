# Playing

All commands run on the lab host: your Ubuntu machine, or the lab VM on a Mac.

```bash
./labctl break --level 1          # random fault. Levels 1 (single obvious failure) to 3 (nasty)
./labctl ticket                   # re-read the ticket
./labctl shell web1               # get onto a box (recorded while a fault is active); or: ssh web1
./labctl status                   # what a customer sees right now
./labctl hint                     # 3 hints per fault, from vague to specific
./labctl commands                 # every command you typed so far, on any node, with exit codes
./labctl check                    # are you done? (symptom gone AND root cause fixed)
./labctl reveal                   # give up: shows root cause, how to spot it, the fix, the lesson
./labctl reset                    # clean lab
./labctl recover                  # after a reboot: redeploy, keep the open incident (see below)
./labctl up --broken --level 2    # deploy with a fault already in place
./labctl reset --ipv6             # clean lab in dual-stack mode (docs/ipv6.md)
```

`check` accepts any fix that restores the service and removes the root cause. It doesn't check
that you typed the reference commands, but it does check that the root cause is gone, so restarting
things until the symptom disappears won't always pass.

## After a reboot (Mac, VM or Linux host)

The nodes are wired together with virtual cables (veth pairs) that only exist while the containers
run. A reboot of the host (or, on a Mac, of OrbStack/Lima or the VM) destroys them. If the containers come back, they boot
**without their data-plane interfaces**, and the lab is broken in ways that have nothing to do with
your exercise. Quick check: `ssh leaf1 ip -br link` shows no `eth1`, `eth2`, ...

Don't debug that. Run:

```bash
./labctl recover
```

`recover` saves the commands you typed so far (`journal/<ts>.commands.part1.log`, merged back into
the command log at the end), redeploys the lab cleanly, and re-injects the **same fault with the
same parameters**. Your journal, hints and timer carry on, and a note in the journal records the
redeploy. With no incident open, use `./labctl reset` instead.

## Listing and reaching the nodes

```bash
./labctl nodes
```

```
NODE         ROLE      STATE    MGMT            DATA-PLANE ADDRESSES
spine1       router    running  172.30.30.11    eth1:10.0.1.0/31 eth2:10.0.1.2/31 eth3:10.0.1.4/31
leaf1        router    running  172.30.30.21    vlan10:10.10.10.1/24 eth1:10.0.1.1/31 eth2:10.0.2.1/31
web1         web       running  172.30.30.42    eth1:10.10.10.11/24
...
```

Other ways to see the same thing: `sudo containerlab inspect -t topology.clab.yml` (the containerlab
view) or `docker ps --filter name=clab-dc-`. Every node is a container named `clab-dc-<node>`.

There are three ways onto a node. All of them run on the lab host.

| Command | Use it for |
|---|---|
| `ssh web1` | Normal access, like a real DC: SSH over the out-of-band management network |
| `./labctl shell web1` | Same as ssh, plus the session's **output** is recorded into the journal |
| `docker exec -it clab-dc-web1 bash` | Break-glass: works even when a node's sshd or management network is broken |
| `docker exec clab-dc-leaf1 vtysh -c 'show bgp summary'` | One-off commands and scripts |

How SSH is set up: `./labctl up` creates a lab-only key (`~/.ssh/netchaos_ed25519`), installs it on
every node as root's authorized key, and writes `~/.ssh/netchaos.conf` (included from `~/.ssh/config`).
So `ssh web1`, `ssh dc-web1`, `scp file db1:/tmp/` and so on all work. Host key checking is off
because the nodes get new host keys on every deploy.

Things to know:

- **sshd listens only on the management IP (eth0, 172.30.30.0/24).** That network is out-of-band,
  like the iDRAC/iLO network in a real DC, so SSH keeps working while you break the data plane.
  The flip side: `ssh db1` from *inside* web1 fails, because `db1.dc.lab` resolves to the
  data-plane address, where nothing listens on port 22. Jump from the lab host, not from node to node.
- **Every command is logged, whichever way you get in** (see [the command log](journal-and-jury.md#the-command-log)). Output is
  recorded for `labctl shell` and interactive `ssh` sessions, but not for `docker exec`.
- Nodes run no systemd: see the [nodes cheat sheet](nodes-cheatsheet.md) for the `svc` equivalents, log locations and HAProxy.

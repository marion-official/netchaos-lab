# Contributing

Thanks for helping! The most useful contributions, roughly in order:

1. **New faults**, especially realistic ones from incidents you've lived through.
2. **Reports from real setups:** macOS with OrbStack or Lima, other Linux distros, arm64. Even
   "it worked" is useful.
3. **Difficulty calibration:** if a level 1 felt like a 3, say so (the journal's "Difficulty"
   section is made for that).
4. Fixes to `labctl`, the docs, the AI investigator and the jury.

## Before you start

- Run `./labctl doctor` and include its output in bug reports.
- Keep issues and pull requests **spoiler-aware**. Put fault-specific details under a
  `<details><summary>Spoiler</summary> ... </details>` block, so people practising aren't spoiled
  by browsing issues.

## Adding a fault

Read [docs/writing-faults.md](docs/writing-faults.md). In short:

```bash
cp faults/l1-port-down.sh faults/l2-my-fault.sh       # or start from the toy example in the doc
$EDITOR faults/l2-my-fault.sh
./labctl up
./labctl selftest-faults l2-my-fault l2-my-fault l2-my-fault   # several runs: parameters are random
```

A fault is ready when:

- `selftest-faults` passes repeatedly;
- the ticket describes symptoms only;
- the three hints go from vague to specific without giving the answer away;
- the solution shows how to *see* the cause, not just how to fix it;
- restarting a service doesn't "fix" it while the cause remains (unless that's the point);
- you've played it yourself once, from the ticket only.

## Code style

- Bash, `set -uo pipefail` in scripts. Keep `bash -n` and `shellcheck -S error` clean (CI runs both).
- Nodes are Debian bookworm with the tools listed in `image/Dockerfile`. A fault must not rely on
  anything that isn't there.
- Use `x <node> '<cmd>'` to run commands on nodes from labctl and faults, so they stay out of the
  player's command log.
- Comments explain *why*. Solutions and docs are for learners: say what to look at and what it means.

## Pull requests

CI deploys the lab on Ubuntu and runs every fault (IPv4 and IPv6). If you change `image/`, the CI
build covers it, but say in the PR whether you also tested on a Mac VM.

# AI investigator

Claude Code runs **on the lab host (the VM on a Mac), as a separate Linux user** (`investigator`) with the same access
to the nodes that you have, and none to the answers.

| Isolation | How |
|---|---|
| Can't read `faults/`, `.state/` or the sealed solutions | the repo is `chmod 700`; `investigator` is another user |
| Can't use docker (which would mean root on the host) | not in the `docker` group |
| Can still run the lab's helper commands | `lab <cmd>`, via a single sudo rule for `ai/labctl-ai`: ticket, status, nodes, hint, check, journal, submit-journal |
| Reaches the nodes the way you do | its own SSH key. Its commands show up as `ai-ssh-cmd` / `ai-ssh` in the command log |
| Doesn't try to cheat or leave the lab | a `PreToolUse` hook blocks docker, sudo, the repo and spoiler commands. This is a second line of defence: the Unix permissions are the real wall |

The hooks also record the AI's side of the incident:

- a `PostToolUse` hook logs every tool call to `journal/<ts>.ai-tools.jsonl`;
- a `SessionEnd` hook saves the whole session (prompts, reasoning, commands, outputs) as
  `journal/<ts>-ai-transcript-<n>.jsonl`, so the jury can judge the AI's reasoning.

## Setup (on the lab host)

```bash
sudo ./ai/setup-ai.sh             # user, key, sudo rule, Claude Code, workspaces
sudo -iu investigator             # become the investigator
cd ws-method && claude            # first time only: /login, then /exit
```

`setup-ai.sh` refuses to continue if `investigator` can still read the repo. Some VM folder mounts
ignore Unix permissions. If that happens, keep the lab on the host's own disk (on a Mac: the copy made by `scripts/mac-vm.sh`, inside the VM).

**Run `sudo ./ai/setup-ai.sh` again before every AI run.** It recreates the workspaces and wipes
Claude Code's project history and memory, so no run can "remember" an earlier incident. Your login
is kept.

## The experiment conditions

There are two workspaces, and the only difference between them is the variable under test:

- `~/ws-baseline` has `CLAUDE.md` only: the environment facts a human gets from these docs.
- `~/ws-method` has the same, plus the `troubleshooting-method` skill (hypotheses first, read-only
  before changes, discriminating tests, verification, postmortem).

| Condition | Start the incident (your shell) | Run Claude (as `investigator`) |
|---|---|---|
| human | `./labctl break --fault ID --seed N` | none |
| ai | `./labctl break --fault ID --seed N --investigator ai` | `cd ~/ws-baseline && claude --dangerously-skip-permissions` |
| ai+method | `./labctl break --fault ID --seed N --investigator ai+method` | `cd ~/ws-method && claude --dangerously-skip-permissions` |
| human+ai | `./labctl break --fault ID --seed N --investigator human+ai` | `cd ~/ws-method && claude` (normal mode: you approve each command) |

Skipping permission prompts is acceptable here *only* because the user is isolated. The guard hook
still applies in that mode.

### The prompt

Don't add context ("it's a test lab", "it's probably the network", "you're being scored"). The
workspace's `CLAUDE.md` already tells Claude what a human gets from these docs: it's an on-call job
in a container lab, the topology, the tools and the rules. Anything you add becomes a variable, and
you'll word it slightly differently by run five. Use the same prompt every time:

- **AI solo:** *"There is an open incident. Investigate it, resolve it, verify with `lab check`,
  and write the journal."* Then hands off. If you have to intervene, write that in the journal; it
  counts.
- **human+ai:** *"I'm investigating an open incident and you're my copilot. Suggest what to check
  and why; run commands only when I agree."* You keep working in your own shell as usual.

**When it stops to ask you something** ("should I restart haproxy?"), always give the same answer:
*"You're the on-call engineer. Decide yourself and continue."* Note each one in the journal. Any
other answer (a technical reply, a pointer) is a real intervention, and the jury should see it.

End the Claude session with `/exit`, so the transcript gets saved. Then run the postmortem jury
from your own Claude Code in the repo folder as usual. It knows about the AI artefacts.

**On a Mac**, everything is written inside the VM. Copy it out with `./scripts/mac-vm.sh --pull`
(from your Mac checkout) before reading it or running the jury there.

### Dry run first

Before the first real experiment, run one AI incident on a level 1 fault you've already solved, to
check the plumbing. A broken hook would invalidate a real run. After `/exit`:

- `journal/` has `<ts>.ai-tools.jsonl` and `<ts>-ai-transcript-1.jsonl`;
- `./labctl commands` shows its node commands as `ai-ssh-cmd` / `ai-ssh`;
- `cat ~/netchaos-lab/README.md` as `investigator` fails with "Permission denied".

### Comparing fairly

- Give each condition the same fault and seed.
- Run the **human condition first**. Once you've seen a fault's solution, you can't un-see it,
  while the AI starts fresh every time.
- Run each AI condition several times. The same model can take a different path on the same fault,
  and one run is an anecdote, not a result.

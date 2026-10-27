# The 7 steps and the journal

Every `break` creates `journal/<timestamp>.md` with the ticket and one section per step:

1. Identify the problem
2. Establish a theory of probable cause
3. Test the theory
4. Establish a plan of action
5. Implement
6. Verify full functionality
7. Document: a short postmortem with fixed headings
   - **Causal chain:** symptom → immediate cause → underlying cause → contributing factors, each
     with its evidence.
   - **Remedy:** the fix applied, whether it's persistent, and the change that removes the root
     cause for good.
   - **Detection:** the alert that would have caught it earlier.
   - **Prevention:** the guard rail that stops it happening again.
   - **What you'd do differently.**

Also set **Investigator** in the journal header (human, ai or human+ai) so reviews can be compared.

## The command log

During an incident, every command typed on any node is logged, however you reached it:

| How you got in | What's logged |
|---|---|
| `ssh web1`, then commands | each command, exit code, directory, **and the session's output** |
| `ssh web1 'cmd'` | the command and its exit code |
| `./labctl shell web1` | each command, exit code, directory, **and the output** |
| `docker exec -it clab-dc-web1 bash` | each command, exit code, directory (no output) |
| `docker exec clab-dc-web1 cmd` | the command (no exit code or output) |

How each part works:

- Inside the nodes, an interactive-bash hook and an sshd wrapper (`audit/node-setup.sh`, pushed in
  at `up` and `break`, so no image rebuild is needed) write to `/var/log/lab/commands.log`.
- On the lab host, a `docker events` recorder catches `docker exec` one-offs.
- labctl's own checks and the fault injection are excluded.

`./labctl commands` shows the log for the current incident at any time. At `check`, `reveal` or
`down` it's saved as `journal/<ts>.commands.log`, next to the output recordings
(`<ts>-<node>.log`, `<ts>-ssh-<node>-*.log`).

Times are UTC, in the logs and in the nodes' prompts.

That's the raw data for the blog: run the same fault (`--fault <id> --seed N`) once without AI and
once with it, and compare commands, failed commands, wrong turns and hints.

## Getting judged: the postmortem jury

`.claude/skills/postmortem-jury/` is a Claude skill that reviews a finished incident like a strict
jury reviewing a postmortem. It judges *how* you troubleshot, not only whether `check` passed.

**Workflow:**

1. `./labctl break`, then investigate however you like. Every command is logged. Prefer
   `ssh` or `./labctl shell` for interactive work, so your output is recorded too: the jury can only
   catch a misread output if it can see the output.
2. `./labctl check` until it passes (or `./labctl reveal`). This also seals the ground truth next to
   the journal as `journal/<ts>.solution.md`.
3. Fill in the journal, **including the postmortem in step 7**. The jury reads causal depth, remedy,
   detection and prevention from there: if you didn't write it down, it can't credit you for it.
4. Start Claude Code in the repo folder (`cd netchaos-lab && claude`) and ask *"run the postmortem jury on
   my last incident"*. To review an older one, name its journal.
   **On a Mac**, the journals live in the VM: either run Claude Code inside the VM, in
   `~/netchaos-lab`, or first copy them to the Mac with `./scripts/mac-vm.sh --pull` and run it in
   your Mac checkout.
5. Read `journal/<ts>.review.md`.

**What it scores** (0-4 each, every score backed by a quote from your journal or command log):

- root-cause accuracy
- causal depth
- hypothesis quality
- evidence quality (did your tests discriminate between hypotheses?)
- efficiency (false leads)
- mistakes, from exit codes and the command sequence: slips, repeated failures, wrong-target
  commands, misread output, changes you later reverted. A failing `ping` that was *meant* to
  test something isn't a mistake.
- safety (risky changes, or changes that only masked the symptom)
- remedy
- verification
- documentation

**Verdict:**

- **PASS** needs the right root cause, no risky or masking changes, and a real fix.
- **PARTIAL** is roughly the right cause.
- **FAIL** is anything else.

**Time:** time is measured as *active* time and in commands. A gap of more than 15 minutes between
commands counts as a pause, so leaving an incident for days doesn't cost you anything.

**The most useful part:** the expert path, the shortest sequence of discriminating commands from
ticket to cause, next to what you actually did. Each review also ends with a YAML block, so you can
compare runs (human vs AI vs human+AI).

**Spoilers:** the jury only opens the ground truth of the incident it reviews, never the rest of
`faults/`.

**Calibrate it before you trust it.** Review one investigation you know was sloppy and one you know
was solid. If the scores don't clearly separate them, the rubric needs tightening.

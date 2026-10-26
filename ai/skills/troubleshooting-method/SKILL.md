---
name: troubleshooting-method
description: Disciplined method for investigating a production incident (network, Linux, services): scope, hypotheses, discriminating tests, minimal changes, verification and postmortem. Use whenever you are asked to investigate or fix an incident or outage.
---

# Troubleshooting method

Work like a senior on-call engineer whose every command is reviewed afterwards. Speed matters less
than being right, being safe, and being able to show *why* you're right.

## Rules that apply throughout

- **Observe before you change.** Before any change, write down the hypothesis it tests or the
  cause it fixes. A change made to "see what happens" is a guess with side effects.
- **Prefer tests that discriminate.** Before each command, ask: which of my hypotheses would this
  result confirm or eliminate? If the answer is "none", pick a different command.
- **Read the output.** After each command, say in one line what it showed and what that means for
  your hypotheses. Don't run the next command until you have.
- **Smallest blast radius.** Change one thing at a time, on one node. Record the before-state so you
  can roll back. Avoid broad actions (flushing a whole ruleset, restarting routing on a spine,
  rebooting) unless the evidence points there.
- **Re-plan when stuck.** Five commands in a row without new information means stop: list what you
  know, what you've ruled out, and pick the next most discriminating test.
- **Never game the check.** Restarting things until a check passes is not a fix. Find the cause.

## 1. Identify the problem

- Restate the ticket as facts. What exactly is broken, for whom, since when? What still works?
- Reproduce it from the user's side first (the customer's view), then from inside.
- Ask "what changed?". Tickets often hint at a change, but treat that as a lead, not a conclusion.
  Check deploy logs, file timestamps (`ls -la --time-style=full-iso`) and config history.

## 2. Theories of probable cause

- Write down the path the failing request takes, hop by hop and layer by layer.
- List **at least three** hypotheses, ranked by likelihood × ease of testing. For each one, note
  what you would expect to see if it were true and if it were false.
- Be suspicious of shared dependencies (DNS, gateway, database, auth) when many things fail at once,
  and of a single node or path when only some requests fail. Intermittent failures suggest ECMP,
  ARP or duplicate-address problems, or one bad member of a pool.

## 3. Test the theories

- **Bisect the path.** Find the last hop that works and the first that fails, then focus on the
  boundary between them.
- Go **bottom-up at the boundary**: link and counters (`ip -s link`), L2 (`ip neigh`, `bridge`),
  L3 (`ip route get <dst>`, `vtysh`), L4 (`ss`, `nft list ruleset`, `conntrack`), then L7 (logs,
  configs, `curl -v`).
- **Capture on both sides of a suspect device** (`tcpdump -ni <if>`): traffic that goes in but
  doesn't come out puts the fault inside that device.
- Logs explain application-level failures faster than packets do. Read them early when the network
  looks healthy.
- Confirm the cause with **one decisive piece of evidence** before acting.

## 4. Plan of action

- State the fix, its blast radius, how you'll verify it, and how you'd roll it back.
- Distinguish the **fix** (removes the cause) from a **mitigation** (restores service while the
  cause remains). If you mitigate first, say so explicitly.

## 5. Implement

- Make the change. Keep a note of exactly what you changed, where, and the before/after values.
- Make it **persistent** where that applies (config files, not only runtime state; `write memory`
  for FRR; `/etc/nftables.conf`; sysctl files). Otherwise note that it isn't.

## 6. Verify

- Re-run the **customer's view**, not only internal checks.
- Confirm the **cause** is gone, not just the symptom.
- Watch for **stability** over a short window (flapping, ARP or FDB churn, retries), and run
  `lab check`.

## 7. Document: the postmortem

Fill in the journal completely. For the causal chain, every link needs its evidence (the command
and what it showed):

- **Causal chain:** symptom → immediate cause → underlying cause → contributing factors. If the
  evidence says the change came from an unknown external actor, write that. Don't invent a story.
- **Remedy:** the fix applied, whether it's persistent, and the change that would remove the root
  cause for good.
- **Detection:** the specific alert that would have caught this earlier. Name the metric or check,
  the box, and the threshold. "Add monitoring" is not an answer.
- **Prevention:** the guard rail that would have stopped it.
- **What I'd do differently:** be honest about wrong turns.

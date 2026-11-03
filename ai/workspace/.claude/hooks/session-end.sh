#!/usr/bin/env bash
# Stop (after every AI turn) and SessionEnd: save the full session transcript (prompts, reasoning,
# tool calls, outputs) next to the incident journal, as <ts>-ai-transcript-<session>.jsonl, for the
# postmortem jury. Saving after every turn means a session that ends without /exit (Ctrl+C, a closed
# terminal) still leaves its transcript behind, at most one turn short. The file is overwritten each
# time, so there is one file per session.
in=$(cat)
tp=$(jq -r '.transcript_path // ""' <<<"$in")
sid=$(jq -r '.session_id // ""' <<<"$in")
[ -f "$tp" ] || exit 0
grep -q '"tool_use"' "$tp" || exit 0          # nothing happened (e.g. a /login-only session): skip
inc=$(cat "$HOME/.netchaos/sessions/$sid" 2>/dev/null)
# redact anything that looks like an Anthropic token/key before it lands in the journal
sed -E 's/sk-ant-[A-Za-z0-9_-]{8,}/[REDACTED]/g' "$tp" \
  | lab ${inc:+--incident "$inc"} save-transcript "$sid" >/dev/null 2>&1
exit 0

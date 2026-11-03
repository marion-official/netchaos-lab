#!/usr/bin/env bash
# SessionEnd: save the full session transcript (prompts, reasoning, tool calls, outputs) next to
# the incident journal, as <ts>-ai-transcript-<n>.jsonl, for the postmortem jury.
tp=$(jq -r '.transcript_path // ""')
# redact anything that looks like an Anthropic token/key before it lands in the journal
[ -f "$tp" ] && sed -E 's/sk-ant-[A-Za-z0-9_-]{8,}/[REDACTED]/g' "$tp" | lab save-transcript >/dev/null 2>&1
exit 0

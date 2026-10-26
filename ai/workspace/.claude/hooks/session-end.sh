#!/usr/bin/env bash
# SessionEnd: save the full session transcript (prompts, reasoning, tool calls, outputs) next to
# the incident journal, as <ts>-ai-transcript-<n>.jsonl, for the postmortem jury.
tp=$(jq -r '.transcript_path // ""')
[ -f "$tp" ] && lab save-transcript < "$tp" >/dev/null 2>&1
exit 0

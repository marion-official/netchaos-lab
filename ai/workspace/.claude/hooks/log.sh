#!/usr/bin/env bash
# PostToolUse / PostToolUseFailure: one JSON line per tool call into the incident's
# <ts>.ai-tools.jsonl (via 'lab ai-log'). The node-side command log already has every ssh command
# with its exit code; this adds the AI's view: local commands, file edits, failures, timing.
# The incident is the one this session was bound to at start (hooks/session-start.sh).
in=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$in" 2>/dev/null)
inc=$(cat "$HOME/.netchaos/sessions/$sid" 2>/dev/null)
jq -c '{
  ts: (now | todate),
  event: .hook_event_name,
  tool: .tool_name,
  input: (.tool_input.command // .tool_input.file_path // .tool_input.skill // (.tool_input | tostring | .[0:300])),
  result: ((.tool_response // .error // "") | tostring | .[0:2000])
}' <<<"$in" 2>/dev/null | sed -E 's/sk-ant-[A-Za-z0-9_-]{8,}/[REDACTED]/g' \
  | lab ${inc:+--incident "$inc"} ai-log 2>/dev/null
exit 0

#!/usr/bin/env bash
# SessionStart: bind this Claude session to the incident that is open RIGHT NOW.
# Every later log, transcript and journal write of the session goes to that incident, even after
# 'lab check' has closed it, and never to an older one. A session started with no incident open is
# bound to "none": its logs go to journal/ai-unattached-*, and 'lab journal' refuses to touch old journals.
in=$(cat)
sid=$(jq -r '.session_id // ""' <<<"$in")
case $sid in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
d="$HOME/.netchaos/sessions"; mkdir -p "$d"
f="$d/$sid"
if [ ! -s "$f" ]; then              # first start of this session (not a resume): record the binding
  inc=$(lab incident 2>/dev/null) || inc=none
  echo "$inc" > "$f"
fi
# the AI's own 'lab ...' commands pick it up from the environment (see /usr/local/bin/lab)
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export LAB_INCIDENT=$(cat "$f")" >> "$CLAUDE_ENV_FILE"
exit 0

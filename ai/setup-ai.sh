#!/usr/bin/env bash
# Setup of the AI investigator INSIDE the Linux VM:   sudo ./ai/setup-ai.sh
# Run it once, and again before EVERY AI run: it recreates fresh workspaces (see below).
#   sudo ./ai/setup-ai.sh --token     # also store a Claude Code token (from 'claude setup-token'),
#                                     # instead of logging in with /login inside the VM
#
# Creates the Linux user 'investigator' that runs Claude Code. Isolation is done with OS
# permissions, not with prompts or hooks (an agent can always try 'cat faults/*.sh'):
#   - no docker group            -> can't docker exec / mount the host
#   - the lab repo is chmod 700  -> can't read faults/, .state/ or the sealed solutions
#   - one sudo rule              -> 'lab <cmd>' runs ai/labctl-ai as the lab owner, which only
#                                   allows ticket/status/nodes/hint/check/journal
#   - its own SSH key            -> reaches the nodes like you do; tagged LAB_ACTOR=ai, so its
#                                   commands appear as ai-ssh / ai-ssh-cmd in the command log
set -euo pipefail
SET_TOKEN=""
for a in "$@"; do
  case $a in --token) SET_TOKEN=1 ;; *) echo "unknown option: $a (only --token)" >&2; exit 1 ;; esac
done
AI_USER=investigator
LAB_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
OWNER=${SUDO_USER:-}
[ "$(id -u)" = 0 ] && [ -n "$OWNER" ] || { echo "run as: sudo ./ai/setup-ai.sh  (from your normal VM user)" >&2; exit 1; }
AI_HOME=/home/$AI_USER
say() { printf '\n>> %s\n' "$*"; }

say "packages (jq for the hooks, curl for the Claude Code installer)"
command -v jq >/dev/null && command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq jq curl; }

say "user $AI_USER (not in the docker group)"
id "$AI_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$AI_USER"
gpasswd -d "$AI_USER" docker >/dev/null 2>&1 || true

say "lock the lab repo away from $AI_USER"
chmod 700 "$LAB_DIR"
if sudo -u "$AI_USER" test -r "$LAB_DIR/labctl" 2>/dev/null || sudo -u "$AI_USER" ls "$LAB_DIR/faults" >/dev/null 2>&1; then
  cat >&2 <<WARN
!! $AI_USER can still read $LAB_DIR: this filesystem ignores Unix permissions for other users
!! (Mac folder mounts in OrbStack/Lima do). The AI could read the answers, so setup STOPPED here:
!! no workspaces, no 'lab' command, no keys were created.
!! Fix: run the lab from the VM's own disk (scripts/mac-vm.sh does this for you), e.g.
!!     cp -a "$LAB_DIR" ~$OWNER/netchaos-lab && cd ~$OWNER/netchaos-lab && sudo ./ai/setup-ai.sh
WARN
  exit 1
fi
echo "   ok: $AI_USER cannot read the repo"

say "SSH key for $AI_USER"
install -d -m 700 -o "$AI_USER" -g "$AI_USER" "$AI_HOME/.ssh"
[ -f "$AI_HOME/.ssh/id_ed25519" ] || sudo -u "$AI_USER" ssh-keygen -q -t ed25519 -N "" -C netchaos-lab-ai -f "$AI_HOME/.ssh/id_ed25519"
install -m 644 -o "$OWNER" "$AI_HOME/.ssh/id_ed25519.pub" "$LAB_DIR/ai/investigator.pub"
{
  echo "# netchaos-lab nodes over the management network (written by ai/setup-ai.sh)"
  sed -nE 's/^ +([a-z0-9-]+): *\{ *mgmt-ipv4: *([0-9.]+),.*/Host \1\n  HostName \2/p' "$LAB_DIR/topology.clab.yml"
  printf 'Host *\n  User root\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n'
  printf '  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n  ConnectTimeout 5\n'
} > "$AI_HOME/.ssh/config"
chown "$AI_USER:$AI_USER" "$AI_HOME/.ssh/config"; chmod 600 "$AI_HOME/.ssh/config"

say "the 'lab' command (sudo rule limited to ai/labctl-ai)"
echo "$AI_USER ALL=($OWNER) NOPASSWD: $LAB_DIR/ai/labctl-ai" > /etc/sudoers.d/netchaos-investigator
chmod 440 /etc/sudoers.d/netchaos-investigator
visudo -cf /etc/sudoers.d/netchaos-investigator >/dev/null
# LAB_INCIDENT is set per Claude session by hooks/session-start.sh (sudo drops the environment,
# so it's passed as an argument): the AI's journal commands then always hit the incident that was
# open when the session started, never an older one.
printf '#!/bin/sh\nexec sudo -n -u %s %s ${LAB_INCIDENT:+--incident "$LAB_INCIDENT"} "$@"\n' "$OWNER" "$LAB_DIR/ai/labctl-ai" > /usr/local/bin/lab
chmod 755 /usr/local/bin/lab

say "fresh Claude Code workspaces (no memory of earlier runs; the login is kept)"
# Claude Code keeps per-project history and memory here. Wiping it prevents an AI run from
# "remembering" an earlier incident. Transcripts are already saved in the lab's journal.
# Before wiping, keep every earlier session's raw transcript: the hooks normally save them, but a
# session can end without them firing, and then this is the only copy left.
arch="$LAB_DIR/journal/ai-sessions-archive/$(date +%Y%m%d-%H%M%S)"
found=$(find "$AI_HOME/.claude/projects" -name '*.jsonl' -size +0 2>/dev/null | head -1 || true)
if [ -n "$found" ]; then
  install -d -o "$OWNER" "$LAB_DIR/journal" "$LAB_DIR/journal/ai-sessions-archive" "$arch"
  { find "$AI_HOME/.claude/projects" -name '*.jsonl' -size +0 -print0 2>/dev/null || true; } |
    while IFS= read -r -d '' f; do
      sed -E 's/sk-ant-[A-Za-z0-9_-]{8,}/[REDACTED]/g' "$f" > "$arch/$(basename "$(dirname "$f")")--$(basename "$f")"
    done
  chown -R "$OWNER" "$arch"
  echo "   archived earlier AI sessions to ${arch#"$LAB_DIR"/}"
fi
rm -rf "${AI_HOME:?}/.claude/projects" "${AI_HOME:?}/.claude/todos" "${AI_HOME:?}/.netchaos/sessions" 2>/dev/null || true
for ws in ws-baseline ws-method; do
  rm -rf "${AI_HOME:?}/$ws.new" && cp -a "$LAB_DIR/ai/workspace" "$AI_HOME/$ws.new"
  if [ "$ws" = ws-method ]; then
    mkdir -p "$AI_HOME/$ws.new/.claude/skills"
    cp -a "$LAB_DIR/ai/skills/troubleshooting-method" "$AI_HOME/$ws.new/.claude/skills/"
  fi
  mkdir -p "$AI_HOME/$ws.new/notes"      # fresh every time: no notes from earlier runs
  rm -rf "${AI_HOME:?}/$ws" && mv "$AI_HOME/$ws.new" "$AI_HOME/$ws"
  chmod +x "$AI_HOME/$ws/.claude/hooks/"*.sh
done
chown -R "$AI_USER:$AI_USER" "$AI_HOME"

say "Claude Code for $AI_USER"
if sudo -u "$AI_USER" -i bash -c 'command -v claude || [ -x ~/.local/bin/claude ]' >/dev/null 2>&1; then
  echo "   already installed"
else
  sudo -u "$AI_USER" -i bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    || echo "!! install failed - install it manually as $AI_USER (see https://code.claude.com/docs)"
fi
grep -q '.local/bin' "$AI_HOME/.bashrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$AI_HOME/.bashrc"

# Optional: authenticate with a long-lived token instead of /login (handy when the login URL
# can't be copied out of the VM terminal). It lives in the investigator's home, NOT in the repo:
# the repo is unreadable for the investigator by design, and it gets synced and committed.
TOKEN_FILE=$AI_HOME/.config/netchaos/claude.env
if [ -n "$SET_TOKEN" ]; then
  say "Claude Code token for $AI_USER"
  echo "   Create one on a machine with a browser (e.g. your Mac): claude setup-token"
  if [ -t 0 ]; then read -rsp "   Paste the token (input hidden): " tok; echo
  else read -r tok || true; fi          # also accepts: sudo ./ai/setup-ai.sh --token < file
  tok=$(printf '%s' "$tok" | tr -d '[:space:]')
  [ -n "$tok" ] || { echo "!! empty token, nothing stored" >&2; exit 1; }
  install -d -m 700 -o "$AI_USER" -g "$AI_USER" "$AI_HOME/.config" "$AI_HOME/.config/netchaos"
  ( umask 077; printf 'export CLAUDE_CODE_OAUTH_TOKEN=%q\n' "$tok" > "$TOKEN_FILE" )
  chown "$AI_USER:$AI_USER" "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"
  unset tok
  echo "   stored in $TOKEN_FILE (readable by $AI_USER only); /login isn't needed"
fi
for rc in .bashrc .profile; do      # .profile too: .bashrc returns early in non-interactive shells
  [ -f "$AI_HOME/$rc" ] || continue
  grep -q 'netchaos/claude.env' "$AI_HOME/$rc" \
    || echo '[ -f ~/.config/netchaos/claude.env ] && . ~/.config/netchaos/claude.env' >> "$AI_HOME/$rc"
done
[ -f "$TOKEN_FILE" ] && echo "   token file present: Claude Code will use it" || true

say "install the AI key on the running lab nodes (if the lab is up)"
sudo -u "$OWNER" "$LAB_DIR/labctl" ssh-setup 2>/dev/null || echo "   lab not running - the key is installed at the next ./labctl up / break"

cat <<DONE

Done. Next steps:
  sudo -iu $AI_USER                 # become the investigator
  cd ws-method && claude            # first time only: log in (/login), then exit
                                    #   (or skip /login: sudo ./ai/setup-ai.sh --token)
  lab ticket ; ssh web1 hostname    # sanity check: ticket readable, nodes reachable
  cat $LAB_DIR/README.md            # must FAIL with 'Permission denied'
See docs/ai-investigator.md for running the experiment conditions.
DONE

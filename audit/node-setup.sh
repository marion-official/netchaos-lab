#!/bin/bash
# Command audit for ONE node. labctl pipes this into every node (docker exec -i ... bash -s) at
# 'up' and 'break', so it works on an already-running lab without rebuilding the image.
#
# Everything ends up in /var/log/lab/commands.log as tab-separated lines:
#   time_utc  node  source  exit_code  cwd  command
# source: shell (interactive bash: ssh, docker exec -it, labctl shell) | ssh-cmd (ssh node 'cmd')
# Interactive ssh sessions are additionally recorded with their output in /var/log/lab/tty/.
set -u
mkdir -p /var/log/lab/tty
touch /var/log/lab/commands.log
chmod 1777 /var/log/lab /var/log/lab/tty 2>/dev/null; chmod 666 /var/log/lab/commands.log

# ---- 1. interactive bash: log every command after it finishes (with its exit code)
cat > /etc/lab-audit.bash <<'EOF'
# netchaos-lab command audit (sourced from /etc/bash.bashrc for interactive shells)
if [ -n "${PS1-}" ] && [ -z "${__LAB_AUDIT-}" ]; then
  __LAB_AUDIT=1
  : "${LAB_SRC:=shell}"
  HISTCONTROL=; HISTTIMEFORMAT=
  __lab_n=""
  __lab_log() {
    local rc=$? n c
    n=$(history 1 | awk '{print $1}')
    if [ -n "$__lab_n" ] && [ -n "$n" ] && [ "$n" != "$__lab_n" ]; then
      c=$(history 1 | sed -E '1s/^ *[0-9]+ +//' | tr '\n\t' '  ' | sed 's/ *$//')
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" \
        "$LAB_SRC" "$rc" "$PWD" "$c" >> /var/log/lab/commands.log 2>/dev/null
    fi
    __lab_n=${n:-x}     # the first prompt only records the starting point
    return $rc
  }
  PROMPT_COMMAND=__lab_log
  PS1='[\t \h \w]# '    # same timestamped prompt everywhere (container clock = UTC)
fi
EOF
grep -q lab-audit.bash /etc/bash.bashrc || echo '[ -f /etc/lab-audit.bash ] && . /etc/lab-audit.bash' >> /etc/bash.bashrc

# ---- 2. ssh: one-off commands are logged; interactive logins are also recorded with output
cat > /usr/local/bin/lab-ssh-gate <<'EOF'
#!/bin/bash
# The AI investigator's key carries environment="LAB_ACTOR=ai" (see labctl ssh_setup):
# its commands are logged with an "ai-" source prefix, so human and AI work can be told apart.
P=""; [ "${LAB_ACTOR-}" = ai ] && P="ai-"
log() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" "$1" "$2" "$PWD" "$3" >> /var/log/lab/commands.log 2>/dev/null; }
if [ -n "${SSH_ORIGINAL_COMMAND-}" ]; then
  case $SSH_ORIGINAL_COMMAND in
    */sftp-server*|internal-sftp*|scp\ *) exec bash -c "$SSH_ORIGINAL_COMMAND" ;;   # file copies: not logged
  esac
  bash -c "$SSH_ORIGINAL_COMMAND"; rc=$?
  log "${P}ssh-cmd" "$rc" "$(printf '%s' "$SSH_ORIGINAL_COMMAND" | tr '\n\t' '  ')"
  exit $rc
fi
export LAB_SRC="${P}ssh"
if [ -t 0 ]; then
  exec script -q -f -a "/var/log/lab/tty/$(date -u +%Y%m%dT%H%M%SZ)-${P}ssh.log" -c "bash -l"
fi
exec bash -l
EOF
chmod 755 /usr/local/bin/lab-ssh-gate
printf 'ForceCommand /usr/local/bin/lab-ssh-gate\nPermitUserEnvironment LAB_ACTOR\n' > /etc/ssh/sshd_config.d/audit.conf
# reload sshd so new connections use the gate (existing sessions are unaffected)
pkill -HUP -f '^sshd: /usr/sbin/sshd' 2>/dev/null || true
# ---- 3. a usable vi
# vi is vim.tiny, which Debian starts in vi-compatible mode: arrow keys type A/B/C/D, backspace
# doesn't delete, undo is one level. backupcopy=yes makes vim write files in place, which the
# files Docker bind-mounts into containers (/etc/resolv.conf, /etc/hosts, /etc/hostname) need:
# replacing them via a new file fails with "Device or resource busy".
cat > /etc/vim/vimrc.tiny <<'EOF'
" netchaos-lab: make vi (vim.tiny) behave like a normal vim
set runtimepath=~/.vim,/var/lib/vim/addons,/usr/share/vim/vimfiles,/usr/share/vim/vim90,/usr/share/vim/vimfiles/after,/var/lib/vim/addons/after,~/.vim/after
set nocompatible
set backspace=indent,eol,start
set backupcopy=yes
set ruler showmode showcmd
set history=200 undolevels=1000
set hlsearch incsearch
set nowrap
EOF

touch /run/lab-audit

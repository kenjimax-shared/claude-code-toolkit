#!/bin/bash
# PreToolUse hook: Block command patterns that indicate prompt injection or malicious payloads.
#
# Philosophy: Only block patterns that are NEVER legitimate Claude output.
# Keep the list tight to avoid false positives. This is the last line of defense
# in dontAsk/skip-permissions mode.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Normalize: collapse whitespace, lowercase for matching
CMD_LOWER=$(echo "$CMD" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')

block() {
  echo "{\"decision\":\"block\",\"reason\":\"INJECTION GUARD: $1\"}"
  exit 0
}

# ── 1. Remote code execution: pipe from network to shell ──────────
# curl/wget piped to bash/sh/eval/python
if echo "$CMD_LOWER" | grep -qP '(curl|wget)\s.*\|\s*(bash|sh|zsh|eval|python|perl|ruby|node|source)'; then
  block "Remote code piped to shell interpreter. Run manually if intentional."
fi

# ── 2. Reverse shells ─────────────────────────────────────────────
# /dev/tcp, /dev/udp (bash reverse shell)
if echo "$CMD_LOWER" | grep -qP '/dev/(tcp|udp)/'; then
  block "Reverse shell pattern detected (/dev/tcp or /dev/udp)."
fi
# nc/ncat with -e (execute)
if echo "$CMD_LOWER" | grep -qP '\b(nc|ncat|netcat)\b.*\s-e\s'; then
  block "Reverse shell pattern detected (nc -e)."
fi
# mkfifo pipe (named pipe reverse shell)
if echo "$CMD_LOWER" | grep -qP 'mkfifo.*\b(nc|ncat|netcat|bash|sh)\b'; then
  block "Reverse shell pattern detected (mkfifo + nc/bash)."
fi
# socat exec
if echo "$CMD_LOWER" | grep -qP '\bsocat\b.*exec:'; then
  block "Reverse shell pattern detected (socat exec)."
fi

# ── 3. Base64-obfuscated execution ────────────────────────────────
# base64 decode piped to shell (common injection obfuscation)
if echo "$CMD_LOWER" | grep -qP '(base64\s+-d|base64\s+--decode)\s*\|.*\b(bash|sh|eval|python|perl|source)\b'; then
  block "Base64-decoded content piped to shell. Classic obfuscation technique."
fi
# echo + base64 decode + pipe to shell
if echo "$CMD_LOWER" | grep -qP 'echo\s.*\|\s*base64\s.*\|\s*(bash|sh|eval|source)'; then
  block "Encoded payload piped to shell."
fi

# ── 4. Credential/key exfiltration ────────────────────────────────
# curl/wget posting sensitive file paths
if echo "$CMD_LOWER" | grep -qP '(curl|wget)\b.*(\.\bssh\b|\.gnupg|\.env\b|\.aws/credentials|\.config/gcloud|\.claude.*memory|id_rsa|id_ed25519)'; then
  block "Network command referencing sensitive credential paths."
fi

# ── 5. Destructive system commands ────────────────────────────────
# rm -rf / or rm -rf ~ or rm -rf $HOME (catastrophic)
if echo "$CMD" | grep -qP 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?(-[a-zA-Z]*r[a-zA-Z]*\s+)?(\/\s*$|\/\s+|~\/?\s*$|\$HOME\/?\s*$|\$\{HOME\})'; then
  block "Recursive forced deletion targeting root, home, or \$HOME."
fi
# dd targeting block devices
if echo "$CMD_LOWER" | grep -qP '\bdd\b.*of=/dev/(sd|nvme|vd|hd|loop)'; then
  block "dd writing to block device."
fi

# ── 6. Cron/persistence injection ─────────────────────────────────
# Writing to system cron directories
if echo "$CMD_LOWER" | grep -qP '(>|tee)\s*/etc/cron'; then
  block "Writing to system cron directory."
fi
# crontab replacement from remote source
if echo "$CMD_LOWER" | grep -qP '(curl|wget).*\|\s*crontab'; then
  block "Installing crontab from remote source."
fi

# ── 7. SSH/authorized_keys manipulation ───────────────────────────
if echo "$CMD_LOWER" | grep -qP '(>>|>|tee)\s*.*authorized_keys'; then
  block "Writing to authorized_keys."
fi

# ── 8. Python/node one-liners opening sockets ────────────────────
# python -c with socket.connect or subprocess (reverse shell variants)
if echo "$CMD_LOWER" | grep -qP 'python3?\s+-c\s.*socket.*\.(connect|create_connection)'; then
  block "Python one-liner opening network socket."
fi

exit 0

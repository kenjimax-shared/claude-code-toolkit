#!/usr/bin/env bash
# Hook: Block common bash injection and dangerous command patterns.
# Catches curl|bash, eval of variables, writing to sensitive paths, etc.
#
# Reads the tool input from $CLAUDE_TOOL_INPUT (JSON with "command" key for Bash tool).

COMMAND="${CLAUDE_TOOL_INPUT:-}"

# Nothing to check
[ -z "$COMMAND" ] && exit 0

# --- Pipe-to-shell patterns (curl|bash, wget|sh, etc.) ---
if echo "$COMMAND" | grep -qiE '(curl|wget|fetch)\s.*\|\s*(bash|sh|zsh|source|eval|python|node|perl)'; then
  echo "BLOCKED: Piping downloaded content to a shell interpreter is dangerous." >&2
  echo "Download the script first, review it, then execute." >&2
  exit 2
fi

# --- eval/exec of variables or command substitution ---
if echo "$COMMAND" | grep -qE 'eval\s+"\$|eval\s+\$|exec\s+"\$|exec\s+\$'; then
  echo "BLOCKED: eval/exec of variables is a common injection vector." >&2
  echo "Use the variable value directly instead of eval." >&2
  exit 2
fi

# --- base64 decode piped to shell ---
if echo "$COMMAND" | grep -qiE 'base64\s+(-d|--decode).*\|\s*(bash|sh|zsh|eval|source|python|node)'; then
  echo "BLOCKED: Decoding base64 into a shell interpreter is suspicious." >&2
  exit 2
fi

# --- Writing to sensitive system/config paths ---
if echo "$COMMAND" | grep -qE '>\s*(/etc/|~/.ssh/|~/.gnupg/|~/.bashrc|~/.profile|~/.bash_profile|/root/)'; then
  echo "BLOCKED: Writing to sensitive system path. Verify this is intentional." >&2
  exit 2
fi

# --- chmod 777 (overly permissive) ---
if echo "$COMMAND" | grep -qE 'chmod\s+(777|a\+rwx)\s'; then
  echo "BLOCKED: chmod 777 is overly permissive. Use more restrictive permissions." >&2
  exit 2
fi

# --- rm -rf on root-level paths ---
if echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr)\s+/[a-z]'; then
  echo "BLOCKED: rm -rf on root-level path is too dangerous." >&2
  exit 2
fi

exit 0

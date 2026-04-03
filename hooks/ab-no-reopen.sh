#!/usr/bin/env bash
# Hook: Block agent-browser "open" on a session that's already running.
# Prevents the ab-safe derivative cascade (session--foo--foo--foo).
#
# Uses the same detection as ab-safe: checks ~/.agent-browser/<session>.pid
# and verifies the PID is alive.

COMMAND="${CLAUDE_TOOL_INPUT:-}"

# Only check commands that use agent-browser with "open"
if ! echo "$COMMAND" | grep -qE "agent-browser.*\bopen\b"; then
  exit 0
fi

# Extract session name: look for --session <name> pattern
SESSION=$(echo "$COMMAND" | grep -oP '(?<=--session\s)[^\s"]+' | head -1)

if [ -z "$SESSION" ]; then
  exit 0
fi

# Same detection as ab-safe's is_session_alive(): check PID file
PID_FILE="$HOME/.agent-browser/${SESSION}.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "BLOCKED: agent-browser session '$SESSION' is already open (PID $PID)." >&2
    echo "Do NOT call 'open' again. Use these commands on the existing session:" >&2
    echo "  agent-browser --session $SESSION snapshot" >&2
    echo "  agent-browser --session $SESSION click @eN" >&2
    echo "  agent-browser --session $SESSION fill @eN \"text\"" >&2
    echo "  agent-browser --session $SESSION navigate \"https://...\"" >&2
    echo "To go to a new URL, use 'navigate' or click links on the page." >&2
    exit 2
  fi
fi

# Also check for derivatives of this session (e.g., session--terminal-name)
for pid_file in "$HOME/.agent-browser/${SESSION}--"*.pid; do
  [ -f "$pid_file" ] || continue
  PID=$(cat "$pid_file" 2>/dev/null)
  DERIV=$(basename "$pid_file" .pid)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "BLOCKED: A derivative session '$DERIV' of '$SESSION' is already running (PID $PID)." >&2
    echo "Use commands on the derivative session instead:" >&2
    echo "  agent-browser --session $DERIV snapshot" >&2
    echo "  agent-browser --session $DERIV click @eN" >&2
    echo "Close the derivative first if you need a fresh session:" >&2
    echo "  agent-browser --session $DERIV close" >&2
    exit 2
  fi
done

exit 0

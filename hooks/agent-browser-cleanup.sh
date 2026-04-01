#!/bin/bash
# Stop hook: Close all agent-browser sessions opened during this terminal session.
# Mirrors the chrome-tab-cleanup.sh pattern for agent-browser.

OWNERS="$HOME/.agent-browser/terminal-owners"
AB_BIN="$HOME/.npm-global/bin/agent-browser"
LOG="$HOME/.agent-browser/ab-cleanup.log"

log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

# Get terminal session ID (same logic as the wrapper)
SESSION_ID=""
if [ -n "${TMUX:-}" ]; then
  SESSION_ID=$(tmux display-message -p '#S' 2>/dev/null)
fi
[ -z "$SESSION_ID" ] && SESSION_ID="pid-$$"

TRACKING_FILE="$OWNERS/${SESSION_ID}.sessions"

if [ ! -f "$TRACKING_FILE" ]; then
  exit 0
fi

count=0
while read -r ab_session; do
  [ -z "$ab_session" ] && continue
  # Only close if the session daemon is still running (socket exists)
  if [ -S "$HOME/.agent-browser/${ab_session}.sock" ]; then
    # Use timeout to avoid hanging on a stuck session
    if AGENT_BROWSER_HEADED=0 timeout 5 "$AB_BIN" --session "$ab_session" close 2>/dev/null; then
      count=$((count + 1))
      log "CLOSED $ab_session (terminal $SESSION_ID)"
    else
      log "FAILED to close $ab_session (terminal $SESSION_ID)"
    fi
  else
    log "SKIP $ab_session (not running, terminal $SESSION_ID)"
  fi
done < "$TRACKING_FILE"

rm -f "$TRACKING_FILE"
# Clean derivative mapping file (used by the safety wrapper)
rm -f "$OWNERS/${SESSION_ID}.map"
log "CLEANUP $SESSION_ID: closed $count agent-browser session(s)"
exit 0

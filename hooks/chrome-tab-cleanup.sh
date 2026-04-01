#!/bin/bash
# Stop hook: Close all tabs opened during this session.
# Runs when Claude Code stops, ensuring no tab accumulation.

CHROME_TABS="$HOME/.claude/lucy/bin/chrome-tabs"
LOG="$HOME/.claude/chrome-tabs/chrome-tabs.log"

# Get session ID (same logic as chrome-tabs)
SESSION_ID=""
if [ -n "${TMUX:-}" ]; then
  SESSION_ID=$(tmux display-message -p '#S' 2>/dev/null)
fi
[ -z "$SESSION_ID" ] && SESSION_ID="pid-$$"

# Check if this session has any tracked tabs
META="$HOME/.claude/chrome-tabs/${SESSION_ID}.json"
if [ ! -f "$META" ]; then
  exit 0
fi

# Count owned tabs before cleanup
OWNED=$(python3 -c "
import json
with open('$META') as f:
    data = json.load(f)
print(len(data.get('owned_tabs', [])))
" 2>/dev/null)

if [ "${OWNED:-0}" = "0" ]; then
  # No owned tabs, just remove session file
  rm -f "$META"
  exit 0
fi

# Run cleanup (closes owned tabs, removes session file)
"$CHROME_TABS" cleanup "$SESSION_ID" 2>/dev/null

exit 0

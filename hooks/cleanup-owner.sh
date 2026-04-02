#!/bin/bash
# Stop hook: clean up session-tmux-owners and snooze-active markers on exit.
# Without this, owner files accumulate forever and crash recovery can't tell
# which sessions were actually alive.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

OWNER_DIR="$HOME/.claude/session-tmux-owners"
SNOOZE_DIR="$HOME/.claude/snooze-active"

# Find the tmux name for this session from the owner files
for f in "$OWNER_DIR"/*; do
  [ -f "$f" ] || continue
  if [ "$(cat "$f" 2>/dev/null)" = "$SESSION_ID" ]; then
    NAME=$(basename "$f")
    rm -f "$f"
    rm -f "$SNOOZE_DIR/$NAME"
    break
  fi
done

exit 0

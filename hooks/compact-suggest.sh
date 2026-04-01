#!/bin/bash
# PreToolUse hook: suggest /compact after many tool calls to prevent context loss.
# Adapted from everything-claude-code (ECC).
# Configurable via env: ECC_COMPACT_THRESHOLD (default 50), ECC_COMPACT_REPEAT (default 25).

THRESHOLD=${ECC_COMPACT_THRESHOLD:-50}
REPEAT=${ECC_COMPACT_REPEAT:-25}

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

COUNTER_FILE="/tmp/claude-compact-${SESSION_ID}"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

SCOPE_CHECK=${ECC_SCOPE_CHECK:-150}

if [ "$COUNT" -eq "$THRESHOLD" ] || \
   ([ "$COUNT" -gt "$THRESHOLD" ] && [ "$COUNT" -lt "$SCOPE_CHECK" ] && [ $(( (COUNT - THRESHOLD) % REPEAT )) -eq 0 ]); then
  echo "[$COUNT tool calls] Consider running /compact to free up context."
fi

if [ "$COUNT" -eq "$SCOPE_CHECK" ] || \
   ([ "$COUNT" -gt "$SCOPE_CHECK" ] && [ $(( (COUNT - SCOPE_CHECK) % REPEAT )) -eq 0 ]); then
  echo "[$COUNT tool calls] This session has been running a while. Check with the user: is the original task done? If so, suggest /clear or opening a new terminal for the next task."
fi

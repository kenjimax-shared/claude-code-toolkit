#!/bin/bash
# Stop hook: trigger auto-eval in the background.
# Fires and forgets so the session exits without delay.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# Fire in background (inherit env for OPENAI_API_KEY)
nohup bash "$HOME/.claude/lucy/bin/auto-eval" "$INPUT" &>/dev/null &

exit 0

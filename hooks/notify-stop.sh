#!/bin/bash
# Stop hook: lightweight logging only.
# Notification handled by Notification hook (idle_prompt) in notify-idle.sh.

STDIN_JSON=$(cat)
LAST_MSG=$(echo "$STDIN_JSON" | jq -r '.last_assistant_message // ""' 2>/dev/null)

TMUX_SESSION=""
if [ -n "$TMUX" ]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null)
fi

# Skip logging for Lucy sub-agent sessions
if [[ "$TMUX_SESSION" == lucy-w-* ]]; then
  exit 0
fi

# Skip logging for background task noise
MSG_LEN=${#LAST_MSG}
if [ "$MSG_LEN" -gt 0 ] && [ "$MSG_LEN" -lt 200 ]; then
  if echo "$LAST_MSG" | grep -qi "background" && echo "$LAST_MSG" | grep -qiE "task|command|completed|finished|just finished"; then
    exit 0
  fi
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') stop hook fired (session: ${TMUX_SESSION:-none})" >> "$HOME/.claude/hooks/notify-stop.log"

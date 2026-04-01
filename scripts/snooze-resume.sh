#!/bin/bash
# Claude Code session snooze/resume script
# 1. Creates a tmux session with Claude resuming the session
# 2. Writes a persistent marker so the code-server extension opens a terminal
# 3. Sends ntfy push notification
# Usage: snooze-resume.sh <session-id> [context-note] [terminal-name]

SESSION_ID="$1"
CONTEXT="${2:-}"
TERM_NAME="${3:-claude}"
SNOOZE_DIR="$HOME/.claude/snooze-active"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: $0 <session-id> [context-note] [terminal-name]"
  exit 1
fi

mkdir -p "$SNOOZE_DIR"

# Kill any existing tmux session with this name (stale from prior run)
tmux kill-session -t "$TERM_NAME" 2>/dev/null

# Create tmux session with Claude resuming (runs immediately, independent of code-server)
tmux new-session -d -s "$TERM_NAME" -c "$HOME/Claude" \
  "claude --dangerously-skip-permissions --resume $SESSION_ID"

# Write persistent marker (extension polls this directory)
echo "$SESSION_ID" > "$SNOOZE_DIR/$TERM_NAME"

# Register tmux name ownership so the naming hook knows this session owns this name
NAME_OWNER_DIR="$HOME/.claude/session-tmux-owners"
mkdir -p "$NAME_OWNER_DIR"
echo "$SESSION_ID" > "$NAME_OWNER_DIR/$TERM_NAME"

echo "Snooze fired: tmux=$TERM_NAME session=$SESSION_ID"

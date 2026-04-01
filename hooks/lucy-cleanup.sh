#!/usr/bin/env bash
# lucy-cleanup.sh (Stop hook)
# When a Claude Code session exits, kill only the Lucy agents IT spawned.
# Does NOT kill other agents in the same group (they may belong to other sessions).

TASKS_FILE="$HOME/.claude/lucy/tasks.json"
LUCY_BIN="$HOME/.claude/lucy/bin"
LOG_FILE="$HOME/.claude/lucy/monitor.log"
CONFIG="$HOME/.claude/lucy/config.sh"

# Get the tmux session name of the exiting terminal
SESSION_NAME=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
[ -z "$SESSION_NAME" ] && exit 0

# Check if tasks.json exists and has content
[ -f "$TASKS_FILE" ] || exit 0

# Find active tasks spawned by THIS specific session (not the whole group)
TASK_IDS=$(jq -r --arg ps "$SESSION_NAME" '
  .[] | select(.parent_session == $ps)
       | select(.status == "running" or .status == "reviewing" or .status == "verifying" or .status == "stuck" or .status == "pr_open")
       | .id' "$TASKS_FILE" 2>/dev/null)

[ -z "$TASK_IDS" ] && exit 0

echo "[$(date '+%H:%M:%S')] lucy-cleanup: session '$SESSION_NAME' exiting, killing spawned tasks: $(echo $TASK_IDS | tr '\n' ' ')" >> "$LOG_FILE"

# Source config for helper functions if available
[ -f "$CONFIG" ] && source "$CONFIG"

for task_id in $TASK_IDS; do
  # Get task details
  TASK=$(jq -c --arg id "$task_id" '.[] | select(.id == $id)' "$TASKS_FILE" 2>/dev/null)
  tmux_name=$(echo "$TASK" | jq -r '.tmux // empty')

  # Kill worker tmux session
  [ -n "$tmux_name" ] && tmux kill-session -t "$tmux_name" 2>/dev/null || true
  # Kill review/verify tmux sessions
  tmux kill-session -t "lucy-r-${task_id}" 2>/dev/null || true
  tmux kill-session -t "lucy-v-${task_id}" 2>/dev/null || true

  # Stop isolated Chrome session if any
  "$LUCY_BIN/chrome-session" stop "$task_id" --merge 2>/dev/null || true

  # Mark as killed in tasks.json
  if type update_task &>/dev/null; then
    update_task "$task_id" "status" '"killed"'
  else
    # Inline update if config wasn't sourced
    TMP=$(mktemp)
    jq --arg id "$task_id" '
      [.[] | if .id == $id then .status = "killed" else . end]
    ' "$TASKS_FILE" > "$TMP" && mv "$TMP" "$TASKS_FILE"
  fi

  echo "[$(date '+%H:%M:%S')] lucy-cleanup: killed $task_id" >> "$LOG_FILE"
done

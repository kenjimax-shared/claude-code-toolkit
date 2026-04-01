#!/bin/bash
# Stop hook: 20-second debounced notification fallback.
# idle_prompt handles most cases; this catches text-only responses where it doesn't fire.

DEBOUNCE_SEC=20

# Need a pane identifier for per-terminal debounce
PANE_ID=""
if [ -n "$TMUX_PANE" ]; then
  PANE_ID="${TMUX_PANE//[^a-zA-Z0-9_]/_}"
elif [ -n "$TMUX" ]; then
  PANE_ID=$(tmux display-message -p '#D' 2>/dev/null | tr -d '%')
fi
[ -z "$PANE_ID" ] && exit 0

DEBOUNCE_FILE="/tmp/claude-stop-debounce-${PANE_ID}"
NOTIFIED_MARKER="/tmp/claude-notified-${PANE_ID}"

# Get tmux session name
TMUX_SESSION=""
[ -n "$TMUX" ] && TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null)

# Skip Lucy sub-agent sessions
[[ "$TMUX_SESSION" == lucy-w-* ]] && exit 0

# Write unique token for this Stop event
MY_TOKEN="${$}_$(date +%s%N)"
echo "$MY_TOKEN" > "$DEBOUNCE_FILE"

# Background: wait 20s, then check if we should notify
(
  sleep "$DEBOUNCE_SEC"

  # Still the latest Stop event? (no newer Stop in 20s = Claude is truly idle)
  [ "$(cat "$DEBOUNCE_FILE" 2>/dev/null)" != "$MY_TOKEN" ] && exit 0

  # Did idle_prompt already handle it? (marker touched within last 90s)
  if [ -f "$NOTIFIED_MARKER" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$NOTIFIED_MARKER" 2>/dev/null || echo 0) ))
    [ "$AGE" -lt 90 ] && rm -f "$NOTIFIED_MARKER" && exit 0
  fi

  # Claude has been idle for 20s and idle_prompt didn't fire. Notify now.
  echo '{"session_id":""}' | bash "$HOME/.claude/hooks/notify-idle.sh"
) &
disown

exit 0

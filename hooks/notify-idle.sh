#!/bin/bash
# Notification hook (idle_prompt): fires only when Claude is genuinely waiting for user input.
# Handles: cascading audio notification (desktop→laptop→phone) + tmux status bar update.

STDIN_JSON=$(cat)
SESSION_ID=$(echo "$STDIN_JSON" | jq -r '.session_id // ""' 2>/dev/null)

# Get tmux session name
TMUX_SESSION=""
if [ -n "$TMUX" ]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null)
fi

# Skip Lucy sub-agent sessions
if [[ "$TMUX_SESSION" == lucy-w-* ]]; then
  exit 0
fi

PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

# Update tmux status bar with current time (12-hour format) + context percentage
if [ -n "$TMUX_SESSION" ]; then
  CTX_PCT=""
  if [ -n "$SESSION_ID" ]; then
    for dir in "$HOME/.claude/projects/-home-YOUR_USER-PROJECT" "$HOME/.claude/projects/-mnt-c-Users-YOUR_USER-PROJECT"; do
      if [ -f "$dir/${SESSION_ID}.jsonl" ]; then
        CTX_PCT=$(tail -50 "$dir/${SESSION_ID}.jsonl" | python3 -c "
import sys, json
last_usage = None
for line in sys.stdin:
    try:
        entry = json.loads(line.strip())
        usage = entry.get('message', {}).get('usage')
        if usage:
            last_usage = usage
    except: pass
if last_usage:
    total = last_usage.get('input_tokens', 0) + last_usage.get('cache_creation_input_tokens', 0) + last_usage.get('cache_read_input_tokens', 0)
    pct = int(round(total / 10000))  # percentage of 1M
    print(f'{pct}%')
" 2>/dev/null)
        break
      fi
    done
  fi
  RAM_PCT=$("$PS_EXE" -NoProfile -NonInteractive -Command "Get-CimInstance Win32_OperatingSystem | ForEach-Object { [math]::Round((\$_.TotalVisibleMemorySize - \$_.FreePhysicalMemory) / \$_.TotalVisibleMemorySize * 100) }" 2>/dev/null | tr -d '\r\n')
  RAM_PCT="${RAM_PCT:-?}%ram"
  TIME_STR=$(date '+%-I:%M%P %-m/%-d')
  if [ -n "$CTX_PCT" ]; then
    echo "${CTX_PCT} | ${RAM_PCT} | ${TIME_STR}" > "/tmp/tmux-last-msg-${TMUX_SESSION}"
  else
    echo "${RAM_PCT} | ${TIME_STR}" > "/tmp/tmux-last-msg-${TMUX_SESSION}"
  fi
  tmux refresh-client -S 2>/dev/null
fi

# Mark that idle_prompt handled this pane (Stop hook debounce checks this)
if [ -n "$TMUX_PANE" ]; then
  touch "/tmp/claude-notified-${TMUX_PANE//[^a-zA-Z0-9_]/_}"
fi

# --- Cascading notification: Desktop → Laptop → Phone ---

# Step 1: Check if user is at the desktop (Windows idle < 5 min)
IDLE_SCRIPT="$(wslpath -w "$HOME/.claude/scripts/win-idle.ps1" 2>/dev/null)"
PLAY_SCRIPT="$(wslpath -w "$HOME/.claude/scripts/win-play.ps1" 2>/dev/null)"
WIN_SOUND="C:\\Users\\YOUR_USER\\.claude\\notify-sound.mp3"

WIN_IDLE=$("$PS_EXE" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$IDLE_SCRIPT" 2>/dev/null | tr -d '\r\n')
WIN_IDLE=${WIN_IDLE:-99999}

if [ "$WIN_IDLE" -lt 300 ] 2>/dev/null; then
  # User is at desktop. Play audio via PowerShell (system-level, works in any app).
  nohup "$PS_EXE" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLAY_SCRIPT" -SoundPath "$WIN_SOUND" > /dev/null 2>&1 &
  disown
  # Tell server desktop handled it (suppress browser audio and ntfy)
  curl -s "http://localhost:9199/notify?session=${TMUX_SESSION}&played=local" > /dev/null 2>&1
else
  # Not at desktop. Let server cascade to laptop browser or phone.
  curl -s "http://localhost:9199/notify?session=${TMUX_SESSION}" > /dev/null 2>&1
fi

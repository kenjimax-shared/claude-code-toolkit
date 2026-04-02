#!/bin/bash
# Stop hook: save a session summary from the transcript.
# Writes to ~/.claude/sessions/YYYY-MM/{tmux-name}_{session-prefix}.md
# Organized by month with human-readable filenames from tmux session names.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# Get tmux session name for readable filename
TMUX_NAME=""
if [ -n "$TMUX" ]; then
  TMUX_NAME=$(tmux display-message -p '#S' 2>/dev/null)
else
  # Walk ancestors to find tmux pane
  pid=$$
  ancestors=""
  while [ "$pid" != "1" ] && [ -n "$pid" ]; do
    ancestors="$ancestors $pid"
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  pane_info=$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null)
  while IFS=' ' read -r ppid sname; do
    case "$ancestors" in *" $ppid"*|"$ppid "*|*" $ppid "*) TMUX_NAME="$sname"; break ;; esac
  done <<< "$pane_info"
fi
# Fall back to session ID prefix if no tmux name
[ -z "$TMUX_NAME" ] || echo "$TMUX_NAME" | grep -qxE '[0-9]+' && TMUX_NAME=""

# Find transcript file
TRANSCRIPT=""
for dir in "$HOME/.claude/projects/-home-user-Claude" "$HOME/.claude/projects/-mnt-c-Users-user-Claude"; do
  if [ -f "$dir/${SESSION_ID}.jsonl" ]; then
    TRANSCRIPT="$dir/${SESSION_ID}.jsonl"
    break
  fi
done
[ -z "$TRANSCRIPT" ] && exit 0

HOOK_TRANSCRIPT="$TRANSCRIPT" HOOK_SESSION_ID="$SESSION_ID" HOOK_TMUX_NAME="$TMUX_NAME" python3 << 'PYEOF'
import json, os
from datetime import datetime

transcript = os.environ["HOOK_TRANSCRIPT"]
session_id = os.environ["HOOK_SESSION_ID"]
tmux_name = os.environ.get("HOOK_TMUX_NAME", "")
sessions_root = os.path.expanduser("~/.claude/sessions")

user_msgs = []
files_modified = set()
tools_used = set()

with open(transcript) as f:
    for line in f:
        try:
            entry = json.loads(line)
        except Exception:
            continue

        etype = entry.get("type")

        if etype == "user":
            msg = entry.get("message", {}).get("content", "")
            if isinstance(msg, str) and msg.strip() and not msg.strip().startswith("<"):
                user_msgs.append(msg.strip()[:300])

        if etype == "assistant":
            content = entry.get("message", {}).get("content", [])
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name", "")
                if name:
                    tools_used.add(name)
                inp = block.get("input", {})
                for key in ("file_path", "path", "command"):
                    val = inp.get(key)
                    if val and isinstance(val, str):
                        if key == "file_path" or (key == "path" and val.startswith("/")):
                            files_modified.add(val)
                        break

now = datetime.now()
month_dir = os.path.join(sessions_root, now.strftime("%Y-%m"))
os.makedirs(month_dir, exist_ok=True)

# Filename: {tmux-name}_{session-prefix}.md or just {session-prefix}.md
import re
prefix = session_id[:8]
safe_tmux = re.sub(r'[^A-Za-z0-9._-]', '_', tmux_name) if tmux_name else None
if safe_tmux:
    filename = f"{safe_tmux}_{prefix}.md"
else:
    filename = f"{prefix}.md"

# Remove any old summary files for this session ID (from prior tmux names)
import glob
for old in glob.glob(os.path.join(sessions_root, "*", f"*_{prefix}.md")):
    if os.path.basename(old) != filename:
        os.remove(old)

summary_file = os.path.join(month_dir, filename)
date_str = now.strftime("%Y-%m-%d %H:%M")

with open(summary_file, "w") as f:
    f.write(f"# {tmux_name or prefix}\n")
    f.write(f"**Date**: {date_str}  \n")
    f.write(f"**Session**: `{session_id}`\n\n")

    if user_msgs:
        f.write("## Conversation\n")
        for msg in user_msgs[-15:]:
            first_line = msg.split("\n")[0][:200]
            f.write(f"- {first_line}\n")
        f.write("\n")

    if files_modified:
        f.write("## Files Touched\n")
        for fp in sorted(files_modified)[:30]:
            f.write(f"- `{fp}`\n")
        f.write("\n")

    if tools_used:
        f.write(f"## Tools: {', '.join(sorted(tools_used))}\n")
PYEOF

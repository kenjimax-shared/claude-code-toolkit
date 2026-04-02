#!/bin/bash
# Stop hook: overwrite the last-prompt entry in the session JSONL with the first prompt.
# This ensures /resume shows the session's original topic, not the latest prompt.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

FIRST_PROMPT_FILE="$HOME/.claude/session-first-prompts/$SESSION_ID"
[ -f "$FIRST_PROMPT_FILE" ] || exit 0

# Find the JSONL transcript
TRANSCRIPT=""
for dir in "$HOME/.claude/projects/-home-user-Claude" "$HOME/.claude/projects/-mnt-c-Users-user-Claude"; do
  if [ -f "$dir/${SESSION_ID}.jsonl" ]; then
    TRANSCRIPT="$dir/${SESSION_ID}.jsonl"
    break
  fi
done
[ -z "$TRANSCRIPT" ] && exit 0

# Append a last-prompt entry with the tmux slug (or first prompt as fallback)
HOOK_FIRST_PROMPT_FILE="$FIRST_PROMPT_FILE" HOOK_SESSION_ID="$SESSION_ID" HOOK_TRANSCRIPT="$TRANSCRIPT" python3 << 'PYEOF'
import json, os

session_id = os.environ["HOOK_SESSION_ID"]
transcript = os.environ["HOOK_TRANSCRIPT"]
first_prompt_file = os.environ["HOOK_FIRST_PROMPT_FILE"]

# Prefer the tmux slug over the raw first prompt
slug_file = os.path.expanduser(f"~/.claude/session-slugs/{session_id}")
display = None
if os.path.isfile(slug_file):
    with open(slug_file) as f:
        display = f.read().strip()

if not display:
    with open(first_prompt_file) as f:
        first_prompt = f.read().strip()
    if not first_prompt:
        exit(0)
    display = first_prompt[:200]
    if len(first_prompt) > 200:
        display += "\u2026"

entry = json.dumps({"type": "last-prompt", "lastPrompt": display, "sessionId": session_id})

with open(transcript, "a") as f:
    f.write(entry + "\n")
PYEOF

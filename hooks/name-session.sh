#!/bin/bash
# Hook: Name tmux session based on first substantive prompt.
# Fires on UserPromptSubmit. Runs once per session (skips trivial prompts).
# Uses Haiku via Anthropic API for smart slugs, falls back to heuristic.

LOG="$HOME/.claude/hooks/name-session.log"
log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

[ -z "$PROMPT" ] && exit 0

# Skip system notifications
case "$PROMPT" in
  '<task-notification>'*|'<system-'*) exit 0 ;;
esac

# --- Helper functions (defined early so they're available everywhere) ---

get_current_tmux_name() {
  if [ -n "$TMUX" ]; then
    tmux display-message -p '#S' 2>/dev/null
    return
  fi
  local ancestors=""
  local pid=$$
  while [ "$pid" != "1" ] && [ -n "$pid" ]; do
    ancestors="$ancestors $pid"
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  local pane_info
  pane_info=$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null) || return 1
  while IFS=' ' read -r ppid sname; do
    case "$ancestors" in
      *" $ppid"*|"$ppid "*|*" $ppid "*) echo "$sname"; return ;;
    esac
  done <<< "$pane_info"
  local parent_tmux
  parent_tmux=$(tr '\0' '\n' < /proc/$PPID/environ 2>/dev/null | grep '^TMUX=' | cut -d= -f2-)
  if [ -n "$parent_tmux" ]; then
    TMUX="$parent_tmux" tmux display-message -p '#S' 2>/dev/null
    return
  fi
}

# Rename tmux session to $SLUG, using $CURRENT_NAME for targeting
rename_tmux_session() {
  if [ -n "$TMUX" ]; then
    tmux rename-session "$SLUG" 2>/dev/null && log "renamed (inside tmux)" && return 0
  fi
  if [ -n "$CURRENT_NAME" ]; then
    tmux rename-session -t "$CURRENT_NAME" "$SLUG" 2>/dev/null && log "renamed '$CURRENT_NAME' (ancestor match)" && return 0
  fi
  local parent_tmux
  parent_tmux=$(tr '\0' '\n' < /proc/$PPID/environ 2>/dev/null | grep '^TMUX=' | cut -d= -f2-)
  if [ -n "$parent_tmux" ]; then
    TMUX="$parent_tmux" tmux rename-session "$SLUG" 2>/dev/null && log "renamed (parent environ)" && return 0
  fi
  log "could not find tmux session"
  return 1
}

# Save ownership and slug files after a rename
save_ownership() {
  NAME_OWNER_DIR="$HOME/.claude/session-tmux-owners"
  mkdir -p "$NAME_OWNER_DIR"
  echo "$SESSION_ID" > "$NAME_OWNER_DIR/$SLUG"
  if [ -n "$CURRENT_NAME" ] && [ "$CURRENT_NAME" != "$SLUG" ]; then
    rm -f "$NAME_OWNER_DIR/$CURRENT_NAME"
  fi
  SLUG_DIR="$HOME/.claude/session-slugs"
  mkdir -p "$SLUG_DIR"
  echo "$SLUG" > "$SLUG_DIR/$SESSION_ID"
}

# --- Check if trivial prompt ---

IS_TRIVIAL=$(HOOK_PROMPT="$PROMPT" python3 << 'PYEOF'
import re, os
prompt = os.environ.get("HOOK_PROMPT", "").strip()
trivial = {
    'continue','resume','fg','yes','no','ok','okay','sure','go','thanks',
    'thank you','yep','yea','yeah','nah','done','next','stop','quit',
    'exit','help','hi','hello','hey','sup','yo','check','fix','look',
}
first_line = prompt.split('\n')[0].strip().lower()
clean_first = re.sub(r'[^a-z0-9 ]', ' ', first_line).strip()
if clean_first in trivial or len(clean_first.split()) <= 1:
    print("TRIVIAL")
else:
    print("OK")
PYEOF
)

if [ "$IS_TRIVIAL" = "TRIVIAL" ]; then
    # Don't bail yet: if tmux is still numeric, try to restore a saved slug
    CURRENT_NAME=$(get_current_tmux_name)
    if echo "$CURRENT_NAME" | grep -qxE '[0-9]+'; then
        SAVED_SLUG_FILE="$HOME/.claude/session-slugs/$SESSION_ID"
        if [ -f "$SAVED_SLUG_FILE" ]; then
            SLUG=$(cat "$SAVED_SLUG_FILE" 2>/dev/null)
            if [ -n "$SLUG" ]; then
                log "RESTORE slug '$SLUG' on trivial prompt (tmux was '$CURRENT_NAME')"
                rename_tmux_session
                save_ownership
                exit 0
            fi
        fi
    fi
    log "SKIP trivial prompt"
    exit 0
fi

# Save the first non-trivial prompt for this session (used by fix-last-prompt.sh)
FIRST_PROMPT_DIR="$HOME/.claude/session-first-prompts"
mkdir -p "$FIRST_PROMPT_DIR"
FIRST_PROMPT_FILE="$FIRST_PROMPT_DIR/$SESSION_ID"
if [ ! -f "$FIRST_PROMPT_FILE" ]; then
    printf '%s' "$PROMPT" > "$FIRST_PROMPT_FILE"
fi

CURRENT_NAME=$(get_current_tmux_name)

# Track which session ID owns each tmux name.
NAME_OWNER_DIR="$HOME/.claude/session-tmux-owners"
mkdir -p "$NAME_OWNER_DIR"

SHOULD_RENAME=false

if [ -z "$CURRENT_NAME" ]; then
  # Not in tmux at all
  exit 0
elif echo "$CURRENT_NAME" | grep -qxE '[0-9]+'; then
  # Default numeric name, always rename
  SHOULD_RENAME=true
else
  # Non-numeric name. Check if this session ID owns it.
  OWNER_FILE="$NAME_OWNER_DIR/$CURRENT_NAME"
  if [ -f "$OWNER_FILE" ]; then
    OWNER_ID=$(cat "$OWNER_FILE" 2>/dev/null)
    if [ "$OWNER_ID" = "$SESSION_ID" ]; then
      log "SKIP already named '$CURRENT_NAME' (owned by this session)"
      exit 0
    else
      # Different session ID in the same tmux session: stale name, re-rename
      log "STALE name '$CURRENT_NAME' owned by $OWNER_ID, this is $SESSION_ID"
      SHOULD_RENAME=true
    fi
  else
    # No owner file exists. This name was set before the tracking system.
    # Claim it for this session so future resumes will re-name.
    echo "$SESSION_ID" > "$OWNER_FILE"
    log "SKIP already named '$CURRENT_NAME' (claimed by $SESSION_ID)"
    exit 0
  fi
fi

if [ "$SHOULD_RENAME" != "true" ]; then
  exit 0
fi

# --- For resumed sessions, try to use the original session's slug ---
# When user does /resume, the prompt often contains the session ID or
# "resume" text. Use the original slug instead of generating from that.
USE_ORIGINAL_SLUG=""
RESUMED_ID=$(echo "$PROMPT" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
if [ -n "$RESUMED_ID" ] && [ -f "$HOME/.claude/session-slugs/$RESUMED_ID" ]; then
  USE_ORIGINAL_SLUG=$(cat "$HOME/.claude/session-slugs/$RESUMED_ID" 2>/dev/null)
  log "RESUME detected: inheriting slug '$USE_ORIGINAL_SLUG' from session $RESUMED_ID"
fi

# Also check: if this session already has a saved slug (e.g. from before
# context compaction), reuse it instead of regenerating
if [ -z "$USE_ORIGINAL_SLUG" ] && [ -f "$HOME/.claude/session-slugs/$SESSION_ID" ]; then
  EXISTING_SLUG=$(cat "$HOME/.claude/session-slugs/$SESSION_ID" 2>/dev/null)
  if [ -n "$EXISTING_SLUG" ]; then
    USE_ORIGINAL_SLUG="$EXISTING_SLUG"
    log "REUSE existing slug '$EXISTING_SLUG' for session $SESSION_ID"
  fi
fi

if [ -n "$USE_ORIGINAL_SLUG" ]; then
  SLUG="$USE_ORIGINAL_SLUG"
else
  # --- Generate slug via Haiku API, fall back to heuristic ---
  SLUG=$(HOOK_PROMPT="$PROMPT" python3 << 'PYEOF'
import json, os, subprocess, re, sys

prompt = os.environ.get("HOOK_PROMPT", "").strip()

# Truncate prompt to ~500 chars to keep API call fast
truncated = prompt[:500]

# Try Anthropic API with Haiku
slug = None
try:
    creds_path = os.path.expanduser("~/.claude/.credentials.json")
    with open(creds_path) as f:
        token = json.load(f)["claudeAiOauth"]["accessToken"]

    body = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 30,
        "messages": [{"role": "user", "content": (
            "You name tmux sessions. Given a user's first prompt to a coding assistant, "
            "output ONLY a 2-5 word hyphenated lowercase slug that captures the core "
            "task or topic. Focus on WHAT they want done, not conversational filler. "
            "Max 30 characters. No explanation, just the slug.\n\n"
            "Prompt: " + truncated
        )}]
    })

    import urllib.request
    api_req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body.encode(),
        headers={
            "x-api-key": token,
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
        },
    )
    with urllib.request.urlopen(api_req, timeout=5) as api_resp:
        resp_body = api_resp.read().decode()

    if resp_body:
        resp = json.loads(resp_body)
        raw = resp.get("content", [{}])[0].get("text", "").strip()
        # Sanitize: lowercase, hyphens only, no special chars, max 30 chars
        raw = raw.lower().strip('`"\' ')
        raw = re.sub(r'[^a-z0-9-]', '-', raw)
        raw = re.sub(r'-+', '-', raw).strip('-')
        if raw and len(raw) >= 3:
            slug = raw[:30]
except Exception:
    pass

# Fallback: heuristic slug generation
if not slug:
    text = prompt.split('\n')[0].strip().lower()
    lines = [l.strip() for l in prompt.split('\n') if l.strip()]
    if len(text.split()) <= 3 and len(lines) > 1:
        text = lines[1].lower()

    sentences = re.split(r'[.!?]\s+', text)
    if len(sentences) > 1:
        action = ['build','fix','create','implement','add','update','set','write',
                  'make','deploy','configure','refactor','debug','resolve','change',
                  'move','remove','delete','install','connect','migrate','optimize',
                  'design','test','check','review','analyze','investigate','problem',
                  'bug','error','issue','broken','wrong','failing','launch',
                  'track','send','find','download','export','import']
        for s in sentences:
            if any(w in s.split() for w in action):
                text = s
                break

    preamble = [
        r'^(hey|hi|hello|yo|sup|okay|ok|sure|right|so|well|alright|yeah|yep|yea|basically|actually|anyway|anyways)\b[,.\s]*',
        r'^(please|pls|plz)\b[,.\s]*',
        r'^(can|could|would|will|should)\s+you\s+(please\s+)?',
        r'^(i\s+want|i\s+need|i\'?d\s+like|i\s+would\s+like)\s+(you\s+)?to\s+',
        r'^(help\s+me|help\s+us)\s+(to\s+)?',
        r'^(i\s+want\s+to|i\s+need\s+to|i\'?d\s+like\s+to)\s+',
        r'^(go\s+ahead\s+and|make\s+sure\s+(to|you)\s+|remember\s+to)\s+',
        r'^(following|this|that|my|our|your)\s+(plan|task|request|thing)[:\s]+',
        r'^let\'?s\s+',
        r'^(look\s+at|check\s+out|take\s+a\s+look\s+at)\s+(the\s+|my\s+|this\s+)?',
    ]
    for _ in range(3):
        prev = text
        for pat in preamble:
            text = re.sub(pat, '', text).strip()
        if text == prev:
            break

    text = re.sub(r'[^a-z0-9 ]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()

    stop = {
        'the','a','an','is','are','was','were','be','been','being',
        'have','has','had','do','does','did','will','would','could',
        'should','may','might','shall','can','to','of','in','for',
        'on','with','at','by','from','as','into','through','during',
        'and','but','or','if','not','no','nor','so','than','too',
        'very','just','also','about','its','my','our','your','their',
        'that','this','it','i','me','we','you','he','she','they',
        'them','us','ll','ve','re','don','doesn','didn','won',
        'all','some','any','each','every','much','many','more',
        'most','other','such','like','get','got','goes','going',
        'been','see','way','need','want','thing','things','there',
        'here','what','when','where','how','why','which','who',
        'still','already','after','before','then','now','up',
    }
    words = [w for w in text.split() if w not in stop and len(w) > 1]
    slug = ''
    count = 0
    for w in words:
        if count >= 4:
            break
        candidate = slug + ('-' if slug else '') + w
        if len(candidate) > 30:
            if slug:
                break
            candidate = w[:30]
        slug = candidate
        count += 1
    slug = slug.strip('-') or 'session'

print(slug)
PYEOF
)
fi

[ -z "$SLUG" ] && SLUG="session"

log "SLUG=$SLUG (was '$CURRENT_NAME')"

rename_tmux_session
save_ownership
exit 0

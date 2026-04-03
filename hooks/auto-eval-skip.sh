#!/bin/bash
# UserPromptSubmit hook: detect "skip end review" and flag the session
# to skip auto-eval on stop. Handles voice transcription variations.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

[ -z "$PROMPT" ] || [ -z "$SESSION_ID" ] && exit 0

# Case-insensitive match on common phrasings (voice transcription varies)
LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

case "$LOWER" in
  *"skip end review"*|*"skip the end review"*|\
  *"skip auto eval"*|*"skip the auto eval"*|\
  *"skip auto review"*|*"skip the auto review"*|\
  *"skip eval"*|*"skip the eval"*|\
  *"no end review"*|*"no auto eval"*|\
  *"skip review at end"*|*"skip final review"*)
    mkdir -p "$HOME/.claude/auto-eval-skip"
    echo "1" > "$HOME/.claude/auto-eval-skip/$SESSION_ID"
    ;;
esac

exit 0

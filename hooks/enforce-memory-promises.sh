#!/bin/bash
# enforce-memory-promises.sh
# Stop hook: catches when Claude promises "saved to memory / won't happen again"
# and forces it to actually implement enforcement at the right level.
#
# Exit 0 = pass (Claude can stop)
# Exit 2 = block (Claude must continue and implement real enforcement)

INPUT=$(cat)

# If this hook already fired this turn, let Claude stop (prevent infinite loop)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Get the last assistant message
MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')

# Nothing to check
if [ -z "$MSG" ]; then
  exit 0
fi

# Lowercase for matching
MSG_LOWER=$(echo "$MSG" | tr '[:upper:]' '[:lower:]')

# Phrases that indicate Claude made a memory-only promise without real enforcement
PATTERNS=(
  "saved to memory"
  "saved this to memory"
  "stored in memory"
  "noted in memory"
  "added to memory"
  "written to memory"
  "updated memory"
  "updated my memory"
  "won't happen again"
  "will not happen again"
  "won't repeat"
  "will not repeat"
  "won't make that mistake"
  "will not make that mistake"
  "i'll remember"
  "i will remember"
  "noted for future"
  "saved for future"
  "i've noted this"
  "i have noted this"
  "recorded this feedback"
  "saved this feedback"
)

MATCHED=""
for pattern in "${PATTERNS[@]}"; do
  if echo "$MSG_LOWER" | grep -qF "$pattern"; then
    MATCHED="$pattern"
    break
  fi
done

# No promise detected, let Claude stop normally
if [ -z "$MATCHED" ]; then
  exit 0
fi

# Check if Claude ALSO mentioned implementing a hook, CLAUDE.md rule, or other enforcement
# If real enforcement was discussed/implemented, don't block
ENFORCEMENT_KEYWORDS=(
  "stop hook"
  "pretooluse"
  "pre-tool-use"
  "claude.md"
  "claudemd"
  "settings.json"
  "enforcement"
  "hook script"
  "exit code 2"
  "userpromptsubmit"
)

for keyword in "${ENFORCEMENT_KEYWORDS[@]}"; do
  if echo "$MSG_LOWER" | grep -qF "$keyword"; then
    # Claude discussed real enforcement alongside the memory save, allow it
    exit 0
  fi
done

# Claude made a memory promise without discussing real enforcement. Block and escalate.
cat >&2 <<'ENFORCE'
STOP: You just promised something is "saved to memory" without implementing real enforcement.

Memory files alone are the WEAKEST form of enforcement (~40% reliability). Before you can finish this response, you MUST:

1. EVALUATE: What behavior needs to be prevented? How critical is it?
2. CHOOSE the right enforcement level:
   - CRITICAL (must never happen): PreToolUse hook that blocks the tool call (95% reliable)
   - IMPORTANT (should be caught): Stop hook that detects and forces revision (85-90% reliable)
   - MODERATE (good to remember): CLAUDE.md rule + memory file (40-60% reliable)
   - MINOR (nice to have): Memory file alone is fine, but say so honestly
3. IMPLEMENT: Actually create/update the enforcement mechanism you chose.
4. REPORT: Tell the user what level you chose, why, and what you implemented.

Do NOT just save a memory file and claim the problem is solved. Be honest about the reliability of whatever you implement.
ENFORCE

exit 2

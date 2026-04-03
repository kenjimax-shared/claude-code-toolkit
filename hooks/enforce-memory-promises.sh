#!/bin/bash
# enforce-memory-promises.sh
# Stop hook: catches when Claude writes/updates a feedback memory file
# without also implementing real enforcement (hook, CLAUDE.md rule, etc.)
#
# Two detection strategies:
# 1. Check tool calls: did Claude write to a feedback memory file this turn?
# 2. Check prose: did Claude promise things won't happen again?
#
# Exit 0 = pass (Claude can stop)
# Exit 2 = block (Claude must continue and implement real enforcement)

INPUT=$(cat)

# If this hook already fired this turn, let Claude stop (prevent infinite loop)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -z "$MSG" ]; then
  exit 0
fi

MSG_LOWER=$(echo "$MSG" | tr '[:upper:]' '[:lower:]')
TRIGGERED=""

# ── Strategy 1: Check if a feedback memory file was written ──
# Look for Write/Edit tool calls to feedback memory files in the transcript
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Check last 200 lines of transcript for writes to feedback memory files
  if tail -200 "$TRANSCRIPT" | grep -qE '"file_path".*memory/feedback_'; then
    TRIGGERED="wrote feedback memory file"
  fi
fi

# ── Strategy 2: Prose pattern matching (broader than before) ──
if [ -z "$TRIGGERED" ]; then
  # Memory-related phrases (catches more variations with regex)
  # Strip code references (backtick content, filenames with extensions) before matching
  MSG_PROSE=$(echo "$MSG_LOWER" | sed -E 's/`[^`]*`//g; s/[a-z0-9_-]+\.(sh|py|js|ts|md|json|yaml|yml|toml)//g')

  MEMORY_PATTERNS=(
    "saved.{0,20}memory"
    "updated.{0,20}memory"
    "update.{0,15}feedback.{0,15}(file|memory)"
    "written.{0,20}memory"
    "stored.{0,20}memory"
    "noted.{0,20}memory"
    "added.{0,20}memory"
    "recorded.{0,15}feedback"
    "saved.{0,15}feedback"
  )

  PROMISE_PATTERNS=(
    "happen again"
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
    "doesn't happen again"
    "does not happen again"
    "prevent this in future"
    "prevent this in the future"
    "so this doesn't"
    "so this won't"
    "this is now fixed"
    "won't skip"
    "will not skip"
    "won't forget"
    "will not forget"
    "won't do that again"
    "will not do that again"
    "won't miss that"
    "will not miss that"
    "that step again"
    "that mistake again"
    "won't overlook"
    "will not overlook"
    "won't happen next"
    "will not happen next"
  )

  for pattern in "${MEMORY_PATTERNS[@]}"; do
    if echo "$MSG_PROSE" | grep -qE "$pattern"; then
      TRIGGERED="prose: $pattern"
      break
    fi
  done

  # Also check promise patterns (even without memory mention, a bare promise should trigger)
  if [ -z "$TRIGGERED" ]; then
    for pattern in "${PROMISE_PATTERNS[@]}"; do
      if echo "$MSG_LOWER" | grep -qF "$pattern"; then
        TRIGGERED="prose: $pattern"
        break
      fi
    done
  fi
fi

# Nothing triggered, let Claude stop
if [ -z "$TRIGGERED" ]; then
  exit 0
fi

# ── Check if Claude ALSO discussed/implemented real enforcement ──
ENFORCEMENT_KEYWORDS=(
  "stop hook"
  "pretooluse"
  "pre-tool-use"
  "posttooluse"
  "post-tool-use"
  "claude.md"
  "settings.json"
  "enforcement"
  "hook script"
  "hook that"
  "hook to"
  "build a hook"
  "create a hook"
  "wrote a hook"
  "exit code 2"
  "userpromptsubmit"
  "type.*prompt"
)

for keyword in "${ENFORCEMENT_KEYWORDS[@]}"; do
  if echo "$MSG_LOWER" | grep -qE "$keyword"; then
    # Real enforcement was discussed alongside the memory save, allow it
    exit 0
  fi
done

# Also check if a hook file was written/edited in this turn's transcript
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if tail -200 "$TRANSCRIPT" | grep -qE '"file_path".*hooks/.*\.sh'; then
    exit 0
  fi
  if tail -200 "$TRANSCRIPT" | grep -qE '"file_path".*settings\.json'; then
    exit 0
  fi
fi

# Claude made a memory/promise without real enforcement. Block and escalate.
cat >&2 <<ENFORCE
STOP: Triggered by: $TRIGGERED
You updated a feedback memory or promised behavioral change without implementing real enforcement.

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

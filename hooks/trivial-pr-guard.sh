#!/bin/bash
# trivial-pr-guard.sh
# Block gh pr create when the diff is trivial (< 10 lines changed).
# Tells Claude to commit directly to main instead.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept gh pr create commands
if ! echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
  exit 0
fi

# Count lines changed (insertions + deletions) vs the base branch
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
STAT=$(git diff --shortstat "$BASE_BRANCH"...HEAD 2>/dev/null)

INSERTIONS=$(echo "$STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
DELETIONS=$(echo "$STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
TOTAL=$((${INSERTIONS:-0} + ${DELETIONS:-0}))

if [ "$TOTAL" -lt 10 ]; then
  echo "BLOCKED: Only $TOTAL lines changed. This is too trivial for a PR." >&2
  echo "Commit directly to main instead:" >&2
  echo "  git checkout main && git pull && git cherry-pick HEAD && git push origin main" >&2
  echo "Then delete the feature branch." >&2
  exit 2
fi

exit 0

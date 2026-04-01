#!/bin/bash
# Cron job: check Google Workspace MCP tokens hourly.
# If any are broken, write a flag file with details.
# If all are OK, remove the flag file.

FLAG_FILE="$HOME/.google_workspace_mcp/tokens_broken"
CHECK_SCRIPT="$HOME/.claude/scripts/check_workspace_tokens.sh"

RESULT=$("$CHECK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    # Extract broken accounts
    echo "$RESULT" | grep "^FAIL" > "$FLAG_FILE"
    echo "$(date -Iseconds)" >> "$FLAG_FILE"
else
    rm -f "$FLAG_FILE"
fi

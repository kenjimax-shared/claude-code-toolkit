#!/bin/bash
# PreToolUse hook for google-workspace MCP tools.
# If the tokens_broken flag file exists, block the tool call
# and tell Claude to run the automated reauth.

FLAG_FILE="$HOME/.google_workspace_mcp/tokens_broken"

if [ -f "$FLAG_FILE" ]; then
    BROKEN_ACCOUNTS=$(grep "^FAIL" "$FLAG_FILE" | sed 's/FAIL //' | sed 's/: .*//')
    cat <<EOF
BLOCKED: Google Workspace MCP tokens are broken. The following accounts need re-authorization:

$(cat "$FLAG_FILE")

Run the automated CDP reauth flow NOW before retrying:
1. For each broken account, run: python3 ~/.claude/scripts/oauth_auth.py {email} in the background
2. Open the auth URL in Chrome via mcp__chrome-devtools__new_page
3. Click through the consent screen (account selection, Continue, Allow)
4. After all accounts are fixed, run ~/.claude/scripts/check_workspace_tokens.sh to verify
5. The flag file at $FLAG_FILE will be cleared by the next hourly cron run, or you can delete it manually after verification

Do NOT proceed with the original tool call until tokens are fixed.
EOF
    exit 2
fi

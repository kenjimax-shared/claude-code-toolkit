#!/bin/bash
# Re-authorize ALL Google Workspace MCP accounts sequentially.
# Each account gets its own OAuth flow with email verification.
# Usage: reauth_all_workspace.sh [email1 email2 ...]
# If no args, re-auths all 4 configured accounts.

set -e

SCRIPT_DIR="$(dirname "$0")"
AUTH_SCRIPT="$SCRIPT_DIR/oauth_auth.py"
CHECK_SCRIPT="$SCRIPT_DIR/check_workspace_tokens.sh"

DEFAULT_EMAILS=(
    "kenji@agency.example.com"
    "user@client.example.com"
    "analytics@agency.example.com"
    "personal@example.com"
)

EMAILS=("${@:-${DEFAULT_EMAILS[@]}}")

echo "=== Google Workspace MCP Re-Authorization ==="
echo "Accounts to re-auth: ${EMAILS[*]}"
echo ""

FAILED=0
for email in "${EMAILS[@]}"; do
    echo "--- Re-authorizing: $email ---"

    # Run oauth_auth.py (it verifies the email matches the token)
    if python3 "$AUTH_SCRIPT" "$email"; then
        echo "OK: $email re-authorized successfully"
    else
        echo "FAIL: $email re-authorization failed"
        FAILED=1
    fi
    echo ""
done

echo "=== Running health check ==="
if "$CHECK_SCRIPT"; then
    echo "All tokens verified correctly."
else
    echo "WARNING: Some tokens are still broken!"
    FAILED=1
fi

exit $FAILED

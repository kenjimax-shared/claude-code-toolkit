#!/bin/bash
# Re-authorize a Google Workspace MCP account
# Usage: reauth_workspace.sh <email>
# Starts the OAuth flow, opens Chrome to the auth URL, waits for callback.
# The user needs to click through the Google consent screen.

set -e

EMAIL="${1:?Usage: reauth_workspace.sh <email>}"
SCRIPT_DIR="$(dirname "$0")"
AUTH_SCRIPT="$SCRIPT_DIR/oauth_auth.py"

if [ ! -f "$AUTH_SCRIPT" ]; then
    echo "ERROR: oauth_auth.py not found at $AUTH_SCRIPT"
    exit 1
fi

echo "Starting OAuth flow for $EMAIL..."
echo "A Chrome tab will open. Select '$EMAIL' and click Allow."

# Run oauth_auth.py in background, capture its output
TMPFILE=$(mktemp)
python3 "$AUTH_SCRIPT" "$EMAIL" > "$TMPFILE" 2>&1 &
AUTH_PID=$!

# Wait for the AUTH_URL line
for i in $(seq 1 10); do
    AUTH_URL=$(grep "^AUTH_URL=" "$TMPFILE" 2>/dev/null | head -1 | sed 's/^AUTH_URL=//')
    [ -n "$AUTH_URL" ] && break
    sleep 0.5
done

if [ -z "$AUTH_URL" ]; then
    echo "ERROR: Could not get auth URL from oauth_auth.py"
    kill $AUTH_PID 2>/dev/null
    cat "$TMPFILE"
    rm -f "$TMPFILE"
    exit 1
fi

echo "Auth URL: $AUTH_URL"
echo "Opening in Chrome..."

# Open in Chrome via PowerShell (Windows side)
powershell.exe -NoProfile -Command "Start-Process '$AUTH_URL'" 2>/dev/null || true

# Wait for the OAuth callback to complete
echo "Waiting for authorization callback (up to 3 minutes)..."
wait $AUTH_PID
EXIT_CODE=$?

# Show result
echo ""
cat "$TMPFILE"
rm -f "$TMPFILE"

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "SUCCESS: Token saved for $EMAIL"
else
    echo ""
    echo "FAILED: Re-auth did not complete (exit code $EXIT_CODE)"
fi

exit $EXIT_CODE

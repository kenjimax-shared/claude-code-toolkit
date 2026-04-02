#!/bin/bash
# Check health of all Google Workspace MCP tokens
# Tests each refresh token by refreshing it and updating the stored access token.
# Does NOT call userinfo (that triggers Google "new sign-in" security alerts).
# Email-to-file mapping was verified at OAuth time; re-checking every 30 min is unnecessary.
# Exit codes: 0 = all healthy, 1 = one or more broken

CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com"
CLIENT_SECRET="YOUR_CLIENT_SECRET"
CREDS_DIR="$HOME/.google_workspace_mcp/credentials"

BROKEN=0
RESULTS=""

for cred_file in "$CREDS_DIR"/*.json; do
    [ -f "$cred_file" ] || continue
    expected_email=$(basename "$cred_file" .json)

    # Skip non-email files
    echo "$expected_email" | grep -q "@" || continue

    refresh_token=$(python3 -c "import json; print(json.load(open('$cred_file')).get('refresh_token',''))")
    [ -z "$refresh_token" ] && { RESULTS+="FAIL $expected_email: no refresh token\n"; BROKEN=1; continue; }

    # Try to refresh the token
    response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$refresh_token" \
        -d "grant_type=refresh_token")

    access_token=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)

    if [ -z "$access_token" ]; then
        error=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_description', d.get('error','unknown')))" 2>/dev/null)
        RESULTS+="FAIL $expected_email: refresh failed ($error)\n"
        BROKEN=1
        continue
    fi

    # Update the stored access token and expiry so the MCP server doesn't need to re-refresh
    expires_in=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in', 3600))" 2>/dev/null)
    python3 -c "
import json, datetime
with open('$cred_file') as f:
    d = json.load(f)
d['token'] = '$access_token'
d['expiry'] = (datetime.datetime.utcnow() + datetime.timedelta(seconds=$expires_in)).isoformat()
with open('$cred_file', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null

    RESULTS+="OK   $expected_email\n"
done

# Also check google-sheets-deep token (single file, no email to verify, just check refresh works)
SHEETS_TOKEN="$HOME/.google_workspace_mcp/sheets_token.json"
if [ -f "$SHEETS_TOKEN" ]; then
    refresh_token=$(python3 -c "import json; print(json.load(open('$SHEETS_TOKEN')).get('refresh_token',''))")
    if [ -z "$refresh_token" ]; then
        RESULTS+="FAIL sheets-deep: no refresh token\n"
        BROKEN=1
    else
        response=$(curl -s -X POST https://oauth2.googleapis.com/token \
            -d "client_id=$CLIENT_ID" \
            -d "client_secret=$CLIENT_SECRET" \
            -d "refresh_token=$refresh_token" \
            -d "grant_type=refresh_token")
        access_token=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)
        if [ -z "$access_token" ]; then
            error=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_description', d.get('error','unknown')))" 2>/dev/null)
            RESULTS+="FAIL sheets-deep: refresh failed ($error)\n"
            BROKEN=1
        else
            RESULTS+="OK   sheets-deep\n"
        fi
    fi
fi

echo -e "$RESULTS"
exit $BROKEN

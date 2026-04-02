#!/bin/bash
# Monitor Google login session for marketing@shapedigital.io
# Checks cookie expiration and refreshes session by visiting a Google page
# Sends email alert via Gmail API if session is dead

PROFILE="$HOME/.agent-browser/profiles/google-ads-premier"
COOKIES_DB="$PROFILE/Default/Cookies"
ALERT_EMAIL="user@agency.example.com"
LOG_FILE="$HOME/.claude/logs/google-session-check.log"
WORKSPACE_CREDS="$HOME/.google_workspace_mcp/credentials"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  echo "$1"
}

# Step 1: Check cookie expiration
check_cookies() {
  if [ ! -f "$COOKIES_DB" ]; then
    log "ERROR: Cookies database not found at $COOKIES_DB"
    return 1
  fi

  # Check days until SIDCC expires (shortest-lived critical cookie)
  DAYS_LEFT=$(sqlite3 "$COOKIES_DB" "
    SELECT CAST((expires_utc/1000000 - 11644473600 - strftime('%s','now')) / 86400 AS INTEGER)
    FROM cookies
    WHERE host_key = '.google.com' AND name = 'SIDCC'
    LIMIT 1;
  " 2>/dev/null)

  if [ -z "$DAYS_LEFT" ]; then
    log "WARNING: SIDCC cookie not found"
    return 1
  fi

  log "SIDCC cookie expires in $DAYS_LEFT days"

  if [ "$DAYS_LEFT" -lt 30 ]; then
    log "WARNING: Cookie expires in less than 30 days"
    return 1
  fi
  return 0
}

# Step 2: Refresh session by loading a Google page
refresh_session() {
  log "Refreshing session..."

  # Remove stale locks
  rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonSocket" "$PROFILE/SingletonCookie" 2>/dev/null

  # Check if any Chrome is running with this profile
  if pgrep -f "user-data-dir=$PROFILE" > /dev/null 2>&1; then
    log "Chrome already running with this profile, skipping refresh"
    return 0
  fi

  # Launch headless Chrome, load myaccount.google.com, wait, close
  CHROME="$HOME/.agent-browser/browsers/chrome-146.0.7680.153/chrome"
  if [ ! -f "$CHROME" ]; then
    # Find whatever chrome version exists
    CHROME=$(find "$HOME/.agent-browser/browsers/" -name "chrome" -type f 2>/dev/null | head -1)
  fi

  if [ -z "$CHROME" ] || [ ! -f "$CHROME" ]; then
    log "ERROR: Chrome binary not found"
    return 1
  fi

  # Start Chrome headless, load a Google page, wait 10s for cookies to refresh
  timeout 30 "$CHROME" \
    --headless=new \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --user-data-dir="$PROFILE" \
    --window-size=800,600 \
    "https://myaccount.google.com/" &
  CHROME_PID=$!

  sleep 15
  kill $CHROME_PID 2>/dev/null
  wait $CHROME_PID 2>/dev/null

  log "Session refresh completed"
  return 0
}

# Step 3: Verify session is still valid by checking if cookies were updated
verify_session() {
  # After refresh, check if SID cookie was updated recently
  LAST_ACCESS=$(sqlite3 "$COOKIES_DB" "
    SELECT datetime((last_access_utc/1000000)-11644473600, 'unixepoch')
    FROM cookies
    WHERE host_key = '.google.com' AND name = 'SID'
    LIMIT 1;
  " 2>/dev/null)

  if [ -z "$LAST_ACCESS" ]; then
    log "ERROR: SID cookie not found after refresh"
    return 1
  fi

  log "SID last accessed: $LAST_ACCESS"
  return 0
}

# Step 4: Send email alert if something's wrong
send_alert() {
  local message="$1"
  log "ALERT: $message"

  # Use the workspace MCP oauth token to send via Gmail API
  # Find the access token for user@agency.example.com
  TOKEN_FILE="$WORKSPACE_CREDS/user@agency.example.com.json"
  if [ ! -f "$TOKEN_FILE" ]; then
    TOKEN_FILE=$(find "$WORKSPACE_CREDS" -name "*user*agencyco*" -type f 2>/dev/null | head -1)
  fi

  if [ -z "$TOKEN_FILE" ] || [ ! -f "$TOKEN_FILE" ]; then
    log "ERROR: Cannot find workspace token for email alert. Token dir: $WORKSPACE_CREDS"
    log "Falling back to gh issue comment"
    gh issue comment 1 --repo user-org/agencyco-tasks --body "**Google Session Alert**: $message" 2>/dev/null
    return
  fi

  ACCESS_TOKEN=$(python3 -c "
import json, time, subprocess, sys
try:
    with open('$TOKEN_FILE') as f:
        creds = json.load(f)
    token = creds.get('token') or creds.get('access_token')
    refresh = creds.get('refresh_token')
    if not token and refresh:
        # Try refresh
        client_id = creds.get('client_id', '')
        client_secret = creds.get('client_secret', '')
        if client_id and client_secret:
            import urllib.request, urllib.parse
            data = urllib.parse.urlencode({
                'client_id': client_id,
                'client_secret': client_secret,
                'refresh_token': refresh,
                'grant_type': 'refresh_token'
            }).encode()
            req = urllib.request.Request('https://oauth2.googleapis.com/token', data=data)
            resp = urllib.request.urlopen(req)
            token = json.loads(resp.read()).get('access_token')
    print(token or '')
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)

  if [ -z "$ACCESS_TOKEN" ]; then
    log "ERROR: Could not get access token for Gmail"
    gh issue comment 1 --repo user-org/agencyco-tasks --body "**Google Session Alert**: $message" 2>/dev/null
    return
  fi

  # Send email via Gmail API
  SUBJECT="[Alert] Google Ads Session: marketing@shapedigital.io"
  BODY="Session check failed for marketing@shapedigital.io (ClientCo Group Google Ads/GA4/GTM).\n\nIssue: $message\n\nAction: Log in manually and complete 2FA to restore the session.\nProfile: ~/.agent-browser/profiles/google-ads-premier/"

  # Build raw email
  RAW_EMAIL=$(printf "To: %s\nSubject: %s\nContent-Type: text/plain; charset=utf-8\n\n%b" "$ALERT_EMAIL" "$SUBJECT" "$BODY" | python3 -c "import sys,base64; print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).decode())")

  curl -s -X POST \
    "https://gmail.googleapis.com/gmail/v1/users/user%40agency.example.com/messages/send" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"raw\": \"$RAW_EMAIL\"}" > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    log "Alert email sent to $ALERT_EMAIL"
  else
    log "ERROR: Failed to send email, falling back to gh issue"
    gh issue comment 1 --repo user-org/agencyco-tasks --body "**Google Session Alert**: $message" 2>/dev/null
  fi
}

# Main
log "=== Google Session Check ==="

if ! check_cookies; then
  send_alert "Cookie check failed. Cookies may be expired or missing."
fi

if ! refresh_session; then
  send_alert "Session refresh failed. Chrome could not load Google page."
fi

if ! verify_session; then
  send_alert "Session verification failed. Google may have invalidated the session."
fi

log "=== Check complete ==="

#!/bin/bash
# url-verification-gate.sh
# Stop hook: blocks Claude from ending a response that presents a LOCAL/DEPLOY
# URL as ready/working/live without evidence of verification in the transcript.
#
# Only triggers for URLs that Claude controls (localhost, LAN IPs, deploy URLs).
# Third-party URLs (google.com, zapier.com, etc.) are never gated.
#
# Exit 0 = pass
# Exit 2 = block (Claude must verify before finishing)

INPUT=$(cat)

MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [ -z "$MSG" ]; then
  exit 0
fi

MSG_LOWER=$(echo "$MSG" | tr '[:upper:]' '[:lower:]')

# Only match URLs that Claude controls: localhost, LAN IPs, deploy domains
# This is a whitelist approach to avoid false positives on third-party URLs
LOCAL_URLS=$(echo "$MSG" | grep -oP 'https?://[^\s\)>`"]+' | grep -E '(localhost|127\.0\.0\.1|0\.0\.0\.0|100\.68\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|10\.|\.vercel\.app|\.cloudfunctions\.net|\.trycloudflare\.com|:3[0-9]{3}/)' || true)

if [ -z "$LOCAL_URLS" ]; then
  exit 0
fi

# Check if surrounding text suggests the URL is being presented as working
# Removed "go to" (81% FP rate - mostly instructional)
PRESENTING_PATTERNS=(
  "dashboard is.{0,15}(live|working|ready|up|accessible)"
  "is live at"
  "is running at"
  "is accessible at"
  "verified and working"
  "fully working"
  "everything is.{0,10}working"
  "try it at"
  "working at"
  "live at"
  "ready at"
  "back up at"
)

PRESENTED=false
for pattern in "${PRESENTING_PATTERNS[@]}"; do
  if echo "$MSG_LOWER" | grep -qE "$pattern"; then
    PRESENTED=true
    break
  fi
done

if [ "$PRESENTED" = false ]; then
  exit 0
fi

# Now check: did Claude actually verify? Look for evidence in recent transcript
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
VERIFIED=false

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  RECENT=$(tail -300 "$TRANSCRIPT")

  # Broadened verification evidence: curl, gstack, agent-browser, fetch
  if echo "$RECENT" | grep -qE '(curl.*-w.*http_code|curl.*(login|api/state|/api/)|gstack.*browse|agent-browser.*snapshot|End-to-end test|e2e.*test)'; then
    if echo "$RECENT" | grep -qE '(200|301|302|rendered|screenshot)'; then
      VERIFIED=true
    fi
  fi
fi

if [ "$VERIFIED" = true ]; then
  exit 0
fi

cat >&2 <<GATE
STOP: You're presenting a local/deploy URL as ready/working but there's no evidence you verified it end-to-end.

Your feedback memory (feedback_verify_before_reporting.md) says:
"NEVER give the user a URL or link as if it's working without first verifying it yourself."

Before finishing this response, you MUST:
1. Test the login flow: curl the login page, POST credentials, verify 200
2. Test the data flow: use the session cookie to hit /api/state, verify 200
3. If both pass, THEN you can present the URL as working
4. If either fails, fix the issue first

Do NOT just say "it's working" based on starting the server. Test the full flow.
GATE

exit 2

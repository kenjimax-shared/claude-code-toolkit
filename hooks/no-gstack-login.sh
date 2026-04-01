#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): Block gstack browse from navigating to login-required sites.
# These sites MUST use agent-browser with persistent profiles instead.
#
# gstack browse (Playwright) shares a single browser instance across all terminals.
# It has no persistent auth, so login-required sites will either fail or create
# session conflicts. agent-browser provides isolated Chrome instances with persistent
# profiles for each service.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only applies to Bash tool
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only check commands that use gstack browse
echo "$CMD" | grep -q "gstack.*browse\|browse/dist/browse" || exit 0

# Only check navigation commands (goto, open, navigate)
echo "$CMD" | grep -qiE "(goto|open|navigate)\b" || exit 0

# Domains that require login and MUST use agent-browser
LOGIN_DOMAINS="
  app.hubspot.com
  tagmanager.google.com
  zapier.com
  app.nextdoor.com
  qbo.intuit.com
  ads.google.com
  analytics.google.com
"

for domain in $LOGIN_DOMAINS; do
  if echo "$CMD" | grep -qi "$domain"; then
    echo "{\"decision\":\"block\",\"reason\":\"Do not use gstack browse for $domain. It requires login and gstack browse has no persistent auth. Use agent-browser with the appropriate profile instead.\"}"
    exit 0
  fi
done

exit 0

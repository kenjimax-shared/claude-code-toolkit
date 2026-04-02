#!/usr/bin/env bash
# Hook: Block gstack browse from being used on login-required sites.
# These sites MUST use agent-browser with persistent profiles instead.
#
# Reads the tool input from $CLAUDE_TOOL_INPUT (JSON with "command" key for Bash tool).

COMMAND="${CLAUDE_TOOL_INPUT:-}"

# Only check commands that use gstack browse
if ! echo "$COMMAND" | grep -q "gstack.*browse\|browse/dist/browse"; then
  exit 0
fi

# Only check navigation commands (goto, open)
if ! echo "$COMMAND" | grep -qiE "(goto|open|navigate)\b"; then
  exit 0
fi

# List of domains that require login and MUST use agent-browser
LOGIN_DOMAINS="app.hubspot.com tagmanager.google.com zapier.com app.nextdoor.com qbo.intuit.com ads.google.com analytics.google.com"

for domain in $LOGIN_DOMAINS; do
  if echo "$COMMAND" | grep -qi "$domain"; then
    echo "BLOCKED: Do not use gstack browse for $domain. Use agent-browser with the appropriate profile instead." >&2
    exit 2
  fi
done

exit 0

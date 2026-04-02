#!/usr/bin/env bash
# PostToolUse hook: When a headless browser gets blocked (e.g., Google's "This browser
# or app may not be secure"), remind Claude to retry in headed mode with DISPLAY=:0
# AGENT_BROWSER_HEADED=1.
#
# Reads tool output from $CLAUDE_TOOL_OUTPUT.

OUTPUT="${CLAUDE_TOOL_OUTPUT:-}"

# Check for common headless-blocked signals
if echo "$OUTPUT" | grep -qiE "browser or app may not be secure|browser.*not supported|unusual traffic|captcha|blocked.*headless|headless.*blocked|Couldn't sign you in"; then
  echo "HINT: Headless browser was blocked. Retry with headed mode: DISPLAY=:0 AGENT_BROWSER_HEADED=1 agent-browser ..." >&2
  exit 0
fi

exit 0

#!/usr/bin/env bash
# PostToolUse hook: When output mentions needing a verification code or magic link
# from email, remind Claude to go fetch it from Gmail instead of asking the user.
#
# Reads tool output from $CLAUDE_TOOL_OUTPUT.

OUTPUT="${CLAUDE_TOOL_OUTPUT:-}"

# Check for verification code / magic link prompts
if echo "$OUTPUT" | grep -qiE "verification code|verify.*email|magic.link|click the link sent to|code sent to|enter.*code.*email|check your email|sent.*verification"; then
  echo "HINT: A verification code was sent to email. Go fetch it yourself from Gmail (via Google Workspace MCP, agent-browser, or Chrome). Do NOT ask the user to get it." >&2
  exit 0
fi

exit 0

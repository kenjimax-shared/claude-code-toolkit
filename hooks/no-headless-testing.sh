#!/usr/bin/env bash
# PreToolUse hook: Block headless browser interaction commands for testing.
#
# gstack browse is ALWAYS headless and should never be used for interactive
# testing (clicks, form fills, JS that dispatches events). Use agent-browser
# in headed mode instead: DISPLAY=:0 AGENT_BROWSER_HEADED=1
#
# Reads the Bash command from $CLAUDE_TOOL_INPUT (JSON with "command" key).

INPUT="${CLAUDE_TOOL_INPUT:-}"
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

# Block gstack browse interaction commands (click, fill, type, js, eval)
if echo "$CMD" | grep -qE '(gstack|browse/dist/browse)\s+(click|fill|type|js|eval|press|check|select|dblclick|hover)'; then
  cat <<'EOF'
BLOCKED: gstack browse is always headless. Do not use it for interactive testing.
Headless browsers get bot-filtered by analytics platforms (GA4, Google Ads, etc.)
and cannot properly trigger link click events.

For testing, use agent-browser in headed mode:
  DISPLAY=:0 AGENT_BROWSER_HEADED=1 ~/.claude/lucy/bin/agent-browser --session <name> --profile ~/.agent-browser/profiles/<name> open <url>

Then use snapshot, click, fill commands on that session.
EOF
  exit 2
fi

exit 0

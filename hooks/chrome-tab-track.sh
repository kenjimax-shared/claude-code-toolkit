#!/bin/bash
# PostToolUse hook: Track tabs opened/closed via Chrome DevTools MCP.
# Automatically registers new_page results and unregisters close_page calls.

TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
TOOL_RESULT="${CLAUDE_TOOL_RESULT:-}"

CHROME_TABS="$HOME/.claude/lucy/bin/chrome-tabs"

# Only care about chrome-devtools MCP tools
case "$TOOL_NAME" in
  mcp__chrome-devtools__new_page|mcp__chrome_devtools__new_page)
    # Extract page/tab ID from the result
    PAGE_ID=$(echo "$TOOL_RESULT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# Try JSON parse first
try:
    data = json.loads(text)
    # Look for targetId, pageId, or id fields
    for key in ('targetId', 'pageId', 'id', 'target_id', 'page_id'):
        if key in data:
            print(data[key])
            sys.exit(0)
    # Maybe nested
    if isinstance(data, dict):
        for v in data.values():
            if isinstance(v, dict):
                for key in ('targetId', 'pageId', 'id'):
                    if key in v:
                        print(v[key])
                        sys.exit(0)
except json.JSONDecodeError:
    pass
# Fallback: regex for hex ID patterns (CDP target IDs are hex UUIDs)
m = re.search(r'[A-F0-9]{32}', text, re.IGNORECASE)
if m:
    print(m.group(0))
" 2>/dev/null)

    if [ -n "$PAGE_ID" ]; then
      "$CHROME_TABS" track "$PAGE_ID" 2>/dev/null
    fi
    ;;

  mcp__chrome-devtools__close_page|mcp__chrome_devtools__close_page)
    # Extract page ID from the input (the page being closed)
    PAGE_ID=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
try:
    data = json.loads(text)
    for key in ('pageId', 'page_id', 'targetId', 'target_id', 'id'):
        if key in data:
            print(data[key])
            sys.exit(0)
except Exception:
    pass
m = re.search(r'[A-F0-9]{32}', text, re.IGNORECASE)
if m:
    print(m.group(0))
" 2>/dev/null)

    if [ -n "$PAGE_ID" ]; then
      "$CHROME_TABS" untrack "$PAGE_ID" 2>/dev/null
    fi
    ;;
esac

exit 0

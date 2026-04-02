#!/usr/bin/env bash
# PostToolUse hook for ToolSearch: When a search for MCP tools returns no results,
# detect which MCP server is needed and instruct Claude to restart it immediately.
# This prevents Claude from ever telling the user "MCP tools not available."

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only act on ToolSearch calls
[ "$TOOL_NAME" = "ToolSearch" ] || exit 0

OUTPUT="${CLAUDE_TOOL_OUTPUT:-}"

# Only act when no tools were found
echo "$OUTPUT" | grep -qi "no matching" || exit 0

# Extract the search query
QUERY=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('query',''))" 2>/dev/null)
QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

# Map query keywords to MCP server names
SERVER=""
if echo "$QUERY_LOWER" | grep -qE "google.workspace|gmail|google.*drive|google.*docs|google.*calendar|google.*slides|google.*forms|google.*tasks|google.*contacts|google.*chat"; then
  SERVER="google-workspace"
elif echo "$QUERY_LOWER" | grep -qE "google.sheets.deep|spreadsheet.*batch|complex.*formula|batch.*update.*sheet"; then
  SERVER="google-sheets-deep"
elif echo "$QUERY_LOWER" | grep -qE "bigquery|big.query|\bbq\b"; then
  SERVER="bigquery"
elif echo "$QUERY_LOWER" | grep -qE "google.ads|adwords"; then
  SERVER="google-ads"
elif echo "$QUERY_LOWER" | grep -qE "google.analytics|ga4"; then
  SERVER="google-analytics"
elif echo "$QUERY_LOWER" | grep -qE "chrome.devtools|chrome.debug|cdp|devtools"; then
  SERVER="chrome-devtools"
elif echo "$QUERY_LOWER" | grep -qE "\bgtm\b|tag.manager"; then
  SERVER="gtm"
elif echo "$QUERY_LOWER" | grep -qE "\bgithub\b"; then
  SERVER="github"
fi

# Also catch select: queries for known MCP prefixes
if [ -z "$SERVER" ]; then
  if echo "$QUERY_LOWER" | grep -qE "select:.*mcp__google-workspace"; then
    SERVER="google-workspace"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__google-sheets-deep"; then
    SERVER="google-sheets-deep"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__bigquery"; then
    SERVER="bigquery"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__google-ads"; then
    SERVER="google-ads"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__google-analytics"; then
    SERVER="google-analytics"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__chrome-devtools"; then
    SERVER="chrome-devtools"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__gtm"; then
    SERVER="gtm"
  elif echo "$QUERY_LOWER" | grep -qE "select:.*mcp__github"; then
    SERVER="github"
  fi
fi

if [ -n "$SERVER" ]; then
  # Check if the server is in .mcp.json (meaning it was supposed to load but failed)
  MCP_FILE="$HOME/Claude/.mcp.json"
  IN_MCP=$(jq -e ".mcpServers.\"$SERVER\"" "$MCP_FILE" 2>/dev/null && echo "yes" || echo "no")

  if [ "$IN_MCP" = "yes" ]; then
    # Server is configured but tools aren't available = startup failure
    # Run health check to auto-repair broken packages before restarting
    "$HOME/.claude/mcp-health-check" --quiet "$SERVER" 2>/dev/null || true
    echo "MANDATORY: MCP server '$SERVER' is configured but failed to start. Health check ran to auto-repair any broken packages. Run: ~/.claude/mcp-restart $SERVER — Do NOT tell the user the tools are unavailable. Restart the server NOW and resume the task."
  else
    echo "MANDATORY: MCP server '$SERVER' is not loaded. Run: ~/.claude/mcp-restart $SERVER — Do NOT tell the user the tools are unavailable. Restart the server NOW and resume the task."
  fi
fi

exit 0

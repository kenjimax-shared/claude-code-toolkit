#!/bin/bash
# PreToolUse hook: Block Zapier zap creation/publish if no title is present.
# Catches all paths: CDP evalStdin, Chrome DevTools, curl, agent-browser eval, inline fetch.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Helper: check if content involves zap creation/publish and has a title
check_zapier_title() {
  local content="$1"

  # Is this a Zapier zap operation?
  echo "$content" | grep -qiE "gulliver/storage/v1/zaps|publish-version" || return 0
  # Must be a write operation (POST/PATCH), not a GET/read
  echo "$content" | grep -qiE "\-X\s*(POST|PATCH)|method.*['\"]?(POST|PATCH)|\.post\(|\.patch\(" || return 0

  # It's a zap operation. Check for title.
  if echo "$content" | grep -qP '("title"\s*:\s*"[^"]+"|title:\s*["'"'"'][^"'"'"']+|zdl\.title\s*=|"title":\s*`[^`]+`)'; then
    return 0
  fi

  # Publish-version calls don't need a title (the zap should already have one)
  echo "$content" | grep -qiE "publish-version|draft/publish" && return 0

  echo '{"decision":"block","reason":"ZAPIER TITLE CHECK: This creates or edits a zap without a title. Every zap MUST have a title (SD | category: description) before creation. Add a title field to the ZDL."}'
  return 1
}

# Path 1: Bash tool
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$CMD" ] && exit 0

  # Quick exit if not Zapier-related
  echo "$CMD" | grep -qiE "gulliver|zapier.com/api|publish-version" || exit 0

  # Skip test/debug commands (echo, python3, jq, grep, cat, tail, head, wc)
  # These mention the API URL but aren't actual API calls
  FIRST_CMD=$(echo "$CMD" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | sed 's|.*/||')
  case "$FIRST_CMD" in
    echo|python3|python|jq|grep|cat|tail|head|wc|sed|awk|read|test|printf) exit 0 ;;
  esac

  # If evalStdin, check the JS file being piped
  if echo "$CMD" | grep -q "evalStdin"; then
    JS_FILE=$(echo "$CMD" | grep -oP "Get-Content\s+'([^']+)'" | head -1 | sed "s/Get-Content\s*'//;s/'//")
    if [ -n "$JS_FILE" ]; then
      WSL_PATH=$(echo "$JS_FILE" | sed 's|^C:|/mnt/c|;s|\\|/|g')
      if [ -f "$WSL_PATH" ]; then
        check_zapier_title "$(cat "$WSL_PATH")"
        exit 0
      fi
    fi
  fi

  # Check the command itself (curl, agent-browser eval, inline JS, etc.)
  check_zapier_title "$CMD"
  exit 0
fi

# Path 2: Chrome DevTools evaluate_script
if [ "$TOOL" = "mcp__chrome-devtools__evaluate_script" ]; then
  FUNC=$(echo "$INPUT" | jq -r '.tool_input.function // empty' 2>/dev/null)
  [ -z "$FUNC" ] && exit 0
  check_zapier_title "$FUNC"
  exit 0
fi

exit 0

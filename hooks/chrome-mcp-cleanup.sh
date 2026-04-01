#!/usr/bin/env bash
# Stop hook: kill any chrome-devtools-mcp node.exe processes spawned by this session.
# Runs on Claude Code exit to prevent orphaned processes from accumulating.

PS="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

# Only run if powershell is available
[ -x "$PS" ] || exit 0

# Kill all chrome-devtools-mcp node.exe processes.
# Since each terminal spawns its own MCP server, and this hook only fires on exit,
# we kill all matching processes. If multiple terminals share the server, the toggle
# script handles re-adding it.
"$PS" -NoProfile -Command '
  Get-CimInstance Win32_Process -Filter "Name=''node.exe'' AND CommandLine LIKE ''%chrome-devtools-mcp%''" |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
' 2>/dev/null

exit 0

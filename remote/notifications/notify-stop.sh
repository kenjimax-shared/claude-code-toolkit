#!/bin/bash
# Stop hook: notify all listening browsers + play locally if at the machine

# Always trigger browser notification (all connected code-server clients poll this)
curl -s http://localhost:9199/notify > /dev/null 2>&1 &

# Optional: Play locally on Windows if console is active and screen is unlocked.
# Uncomment and adjust the path if you set up notify-local.ps1:
# powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$USERPROFILE\.claude\hooks\notify-local.ps1" > /dev/null 2>&1 &

wait

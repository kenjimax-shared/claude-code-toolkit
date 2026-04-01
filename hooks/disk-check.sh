#!/bin/bash
# Disk space check for Claude Code PreToolUse hook
# Caches result for 5 minutes to avoid overhead on every Bash call
# Exits 0 (silent) if all drives OK, exits 2 with JSON to block tool use if low

CACHE="/tmp/disk-check-cache"
CACHE_TTL=300  # seconds

# Skip check if cache is fresh and last result was OK
if [[ -f "$CACHE" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt $CACHE_TTL ]]; then
  status=$(cat "$CACHE")
  if [[ "$status" == "ok" ]]; then
    exit 0
  fi
  # If cached status is not "ok", re-check (drive might have been freed)
fi

THRESHOLD_GB=10
low=""
for pair in "WSL (ext4):/" "C: drive:/mnt/c" "A: drive:/mnt/a"; do
  label="${pair%%:*}"
  mount="${pair#*:}"
  avail_gb=$(df -BG "$mount" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
  if [[ -n "$avail_gb" ]] && (( avail_gb < THRESHOLD_GB )); then
    low+="$label: ${avail_gb}GB remaining. "
  fi
done

if [[ -n "$low" ]]; then
  echo "low" > "$CACHE"
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"LOW DISK SPACE: ${low}Free up space before continuing."}}
EOF
  exit 2
fi

echo "ok" > "$CACHE"

#!/usr/bin/env bash
# Lucy configuration
# Customize paths and settings for your environment.

# Paths
LUCY_DIR="$HOME/.claude/lucy"
LUCY_BIN="$LUCY_DIR/bin"
WORKTREE_ROOT="$HOME/Claude"
TASKS_FILE="$LUCY_DIR/tasks.json"
HISTORY_FILE="$LUCY_DIR/history.json"

# Notification (replace with your notification endpoint)
NOTIFY_URL="http://localhost:9199/notify"
NTFY_TOPIC="your-ntfy-topic-here"

# Defaults
DEFAULT_MODEL="sonnet"
MAX_RETRIES=3
MAX_CONCURRENT=${LUCY_MAX_CONCURRENT:-10}
MIN_AVAIL_MEM_MB=${LUCY_MIN_AVAIL_MEM_MB:-4096}

# Rate limit handling: transient TPM/RPM deaths get extra retries
RATE_LIMIT_BONUS_RETRIES=${LUCY_RATE_LIMIT_BONUS_RETRIES:-5}

# Model mappings (friendly name -> actual model ID)
declare -A MODEL_MAP=(
  [sonnet]="claude-sonnet-4-6"
  [opus]="claude-opus-4-6"
  [haiku]="claude-haiku-4-5"
  [codex]="o3"
  [codex-max]="gpt-5.1-codex-max"
  [codex-mini]="gpt-5.1-codex-mini"
  [gpt54]="gpt-5.4"
)

# Agent binary mappings
declare -A AGENT_BIN=(
  [sonnet]="claude"
  [opus]="claude"
  [haiku]="claude"
  [codex]="codex"
  [codex-max]="codex"
  [codex-mini]="codex"
  [gpt54]="codex"
)

# Repo -> group mapping (customize for your businesses/projects)
# Used for siloing agent context and business knowledge
declare -A REPO_GROUP_MAP=(
  # Example:
  # [MyProject]="myproject"
  # [ClientRepo]="client"
)
DEFAULT_GROUP="default"

# tmux session prefix for Lucy agents
TMUX_PREFIX="lucy"

# Auto-select model based on task type and description complexity
auto_select_model() {
  local type="$1"
  local desc_lower
  desc_lower=$(echo "$2" | tr '[:upper:]' '[:lower:]')

  # Hard problem indicators -> higher reasoning model
  if echo "$desc_lower" | grep -qE '(architect|redesign|security audit|full migration|rewrite from scratch|overhaul|distributed system|concurrency|race condition|complex algorithm|performance critical)'; then
    echo "gpt54"
    return
  fi

  echo "$DEFAULT_MODEL"
}

# Agent command builders
build_agent_cmd() {
  local agent="$1"
  local model_id="$2"
  local prompt_file="$3"
  local log_file="$4"

  if [ "$agent" = "claude" ]; then
    echo "claude --model $model_id --dangerously-skip-permissions --verbose --output-format stream-json -p \"\$(cat $prompt_file)\" > $log_file 2>&1; exit"
  elif [ "$agent" = "codex" ]; then
    local extra_args=""
    if [ "$model_id" = "gpt-5.4" ]; then
      extra_args="-c reasoning_effort=xhigh"
    fi
    echo "codex exec --model $model_id $extra_args --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \"\$(cat $prompt_file)\" > $log_file 2>&1; exit"
  fi
}

# Parse a stream-json log to extract human-readable activity
parse_agent_log() {
  local log_file="$1"
  local lines="${2:-20}"
  if [ ! -f "$log_file" ]; then
    echo "(no log yet)"
    return
  fi
  tail -n 200 "$log_file" | while IFS= read -r line; do
    type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    case "$type" in
      assistant)
        msg=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null)
        [ -n "$msg" ] && echo "[AGENT] $msg"
        tool=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_use") | "\(.name) \(.input | keys | join(", "))"' 2>/dev/null)
        [ -n "$tool" ] && echo "[TOOL] $tool"
        ;;
    esac
  done | tail -"$lines"
}

# Task file helpers (safe concurrent access)
read_tasks() {
  if [ ! -f "$TASKS_FILE" ]; then
    echo "[]"
    return
  fi
  cat "$TASKS_FILE"
}

write_tasks() {
  cat > "$TASKS_FILE"
}

get_task() {
  local id="$1"
  read_tasks | jq -c ".[] | select(.id == \"$id\")" 2>/dev/null
}

update_task() {
  local id="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp=$(mktemp)
  read_tasks | jq "[.[] | if .id == \"$id\" then .${key} = ${value} else . end]" > "$tmp" && mv "$tmp" "$TASKS_FILE"
}

# Notification helper
notify() {
  local title="$1"
  local message="$2"
  curl -s "${NOTIFY_URL}?title=$(echo "$title" | jq -sRr @uri)&message=$(echo "$message" | head -c 100 | jq -sRr @uri)" >/dev/null 2>&1 || true
}

# Logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LUCY_DIR/lucy.log"
}

# Rate limit detection
is_rate_limit_death() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  tail -20 "$log_file" | grep -qiE '(rate.limit|429|tokens?.per.minute|requests?.per.minute|overloaded)' 2>/dev/null
}

# Initialize tasks file if it doesn't exist
[ -f "$TASKS_FILE" ] || echo "[]" > "$TASKS_FILE"

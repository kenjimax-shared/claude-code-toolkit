#!/usr/bin/env bash
# Lucy configuration

# Paths
LUCY_DIR="$HOME/.claude/lucy"
LUCY_BIN="$LUCY_DIR/bin"
WORKTREE_ROOT="$HOME/Claude"
TASKS_FILE="$LUCY_DIR/tasks.json"
HISTORY_FILE="$LUCY_DIR/history.json"

# Notification
NOTIFY_URL="http://localhost:9199/notify"
NTFY_TOPIC="YOUR_NTFY_TOPIC"

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

# Auto-select model based on task type and description complexity
# Used by lucy-spawn when --model is not explicitly provided
auto_select_model() {
  local type="$1"
  local desc_lower
  desc_lower=$(echo "$2" | tr '[:upper:]' '[:lower:]')

  # Hard problem indicators → gpt54 (GPT-5.4 xhigh reasoning)
  if echo "$desc_lower" | grep -qE '(architect|redesign|security audit|full migration|rewrite from scratch|overhaul|distributed system|concurrency|race condition|complex algorithm|performance critical)'; then
    echo "gpt54"
    return
  fi

  # Default
  echo "$DEFAULT_MODEL"
}

# ── Safe identifier validation ─────────────────────────────────────
# Rejects anything that isn't a strict safe identifier.
# Used for task IDs, slugs, group names, context filenames.
validate_identifier() {
  local value="$1"
  local label="${2:-identifier}"
  if [[ ! "$value" =~ ^[a-z0-9][a-z0-9._-]{0,127}$ ]]; then
    echo "Error: $label '$value' contains unsafe characters. Only [a-z0-9._-], max 128 chars, must start with [a-z0-9]." >&2
    return 1
  fi
}

# ── Locked file operations ─────────────────────────────────────────
TASKS_LOCK="$TASKS_FILE.lock"

# Agent command builders
build_agent_cmd() {
  local agent="$1"
  local model_id="$2"
  local prompt_file="$3"
  local log_file="$4"

  if [ "$agent" = "claude" ]; then
    # stream-json gives real-time output; exit tmux when done so monitor detects completion
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
# Extracts: assistant messages, tool calls, tool results (summarized)
parse_agent_log() {
  local log_file="$1"
  local lines="${2:-20}"
  if [ ! -f "$log_file" ]; then
    echo "(no log yet)"
    return
  fi
  # Extract assistant text and tool usage from stream-json
  tail -n 200 "$log_file" | while IFS= read -r line; do
    type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    case "$type" in
      assistant)
        # Assistant text output
        msg=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null)
        [ -n "$msg" ] && echo "[AGENT] $msg"
        # Tool use
        tool=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_use") | "\(.name) \(.input | keys | join(", "))"' 2>/dev/null)
        [ -n "$tool" ] && echo "[TOOL] $tool"
        ;;
      result)
        # Tool result (truncated)
        result=$(echo "$line" | jq -r '.content // empty' 2>/dev/null | head -c 200)
        [ -n "$result" ] && echo "[RESULT] ${result}..."
        ;;
    esac
  done | tail -n "$lines"
}

# Detect if agent death was due to API rate limiting (OpenAI TPM/RPM, Anthropic, etc.)
is_rate_limit_death() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  tail -c 20000 "$log_file" 2>/dev/null | grep -qiE 'rate.limit|429|tokens? per min|TPM.*(Limit|Used)|RPM.*(Limit|Used)|too many requests' 2>/dev/null
}

# Group mappings: repo name -> group
declare -A REPO_GROUP_MAP=(
  [ExampleCo]="exampleco"
  [spaced-rep]="personal"
  [ClientSplash]="clientsplash"
  [clientco-group]="premier"
  [client-flooring]="spartanmat"
  [client-composites]="client-composites"
  [client-sleeve]="smartsleeve"
  [client-weather]="fods"
  [ClientFODS]="fods"
  [client-paloma]="client-paloma"
  [client-health]="client-health"
  [agencyco]="agencyco"
)
DEFAULT_GROUP="default"

# tmux session prefix
TMUX_PREFIX="lucy"

# Logging
LOG_FILE="$LUCY_DIR/monitor.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Send notification through the central server (handles smart routing: audio + ntfy)
notify() {
  local title="${1:-Lucy}"
  local message="${2:-}"
  curl -s "$NOTIFY_URL?session=lucy-orch" >/dev/null 2>&1 || true
}

# Read tasks.json safely
read_tasks() {
  if [ -f "$TASKS_FILE" ]; then
    cat "$TASKS_FILE"
  else
    echo "[]"
  fi
}

# Write tasks.json atomically (unique temp file, no shared .tmp path)
write_tasks() {
  local tmp
  tmp=$(mktemp "$TASKS_FILE.XXXXXX")
  cat > "$tmp"
  mv "$tmp" "$TASKS_FILE"
}

# Get a single task by ID (uses --arg to prevent jq injection)
get_task() {
  local task_id="$1"
  read_tasks | jq -r --arg tid "$task_id" '.[] | select(.id == $tid)'
}

# Update a task field (flock + --arg for safe concurrent writes)
update_task() {
  local task_id="$1"
  local field="$2"
  local value="$3"
  (
    flock -x 200
    local tmp
    tmp=$(mktemp "$TASKS_FILE.XXXXXX")
    read_tasks | jq --arg tid "$task_id" "map(if .id == \$tid then .$field = $value else . end)" > "$tmp"
    mv "$tmp" "$TASKS_FILE"
  ) 200>"$TASKS_LOCK"
}

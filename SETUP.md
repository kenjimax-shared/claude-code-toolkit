# Setup Guide: Placeholders & Configuration

This file lists every placeholder that needs to be filled in to make the toolkit functional. Search for each placeholder string in the codebase to find where it's used.

## Quick Start

1. Clone this repo
2. Run through each section below, filling in your values
3. Copy config files to their destinations (see [File Placement](#file-placement))
4. Add `.bashrc` lines from `config/bashrc.example`
5. Set up cron jobs from `crontab.example`
6. Install dependencies (see [Dependencies](#dependencies))

---

## 1. Authentication & API Credentials

### Claude Code / Anthropic
| Placeholder | File(s) | Description |
|---|---|---|
| (none) | - | Claude CLI authenticates via `claude login`; no config file needed |

### MCP Server Credentials (`config/mcp-templates.json`, `config/.mcp.json`)
| Placeholder | Description |
|---|---|
| `YOUR_GOOGLE_WORKSPACE_TOKEN` | OAuth token for Google Workspace MCP (Drive, Gmail, Calendar, etc.) |
| `YOUR_BIGQUERY_PROJECT_ID` | GCP project ID for BigQuery MCP |
| `YOUR_GITHUB_TOKEN` | GitHub personal access token for GitHub MCP |
| `YOUR_GOOGLE_ADS_DEVELOPER_TOKEN` | Google Ads API developer token |
| `YOUR_GOOGLE_ADS_MCC_ID` | Google Ads MCC (manager) account ID |
| `YOUR_GOOGLE_ADS_CLIENT_ID` | OAuth client ID for Google Ads |
| `YOUR_GOOGLE_ADS_CLIENT_SECRET` | OAuth client secret for Google Ads |
| `YOUR_GOOGLE_ADS_REFRESH_TOKEN` | OAuth refresh token for Google Ads |
| `YOUR_GA4_CLIENT_ID` | OAuth client ID for Google Analytics |
| `YOUR_GA4_CLIENT_SECRET` | OAuth client secret for Google Analytics |
| `YOUR_GA4_REFRESH_TOKEN` | OAuth refresh token for Google Analytics |
| `YOUR_CHROME_DEBUG_HOST` | Chrome DevTools host (default: `localhost`) |
| `YOUR_CHROME_DEBUG_PORT` | Chrome DevTools port (default: `9222`) |

### Notification System (`scripts/notify-server.js`, `lucy/config.sh`)
| Placeholder | Description |
|---|---|
| `your-ntfy-topic-here` | ntfy.sh topic for mobile push notifications |
| `YOUR_REMOTE_HOST:8443` | Your remote access URL (Tailscale, Cloudflare Tunnel, etc.) for click-through links in ntfy notifications |

### agent-browser (`config/bashrc.example`)
| Placeholder | Description |
|---|---|
| `~/.agent-browser/.encryption-key` | Generate with `openssl rand -hex 32 > ~/.agent-browser/.encryption-key` |

---

## 2. Paths & Environment

### User Paths (`lucy/config.sh`)
| Variable | Default | Description |
|---|---|---|
| `LUCY_DIR` | `$HOME/.claude/lucy` | Lucy orchestrator data directory |
| `LUCY_BIN` | `$LUCY_DIR/bin` | Lucy scripts directory |
| `WORKTREE_ROOT` | `$HOME/Claude` | Root directory for git worktrees |
| `TASKS_FILE` | `$LUCY_DIR/tasks.json` | Active tasks database |
| `HISTORY_FILE` | `$LUCY_DIR/history.json` | Completed tasks archive |

### Claude Binary Path (`lucy/bin/claude`, `lucy/bin/claude-isolated`)
| Placeholder | Description |
|---|---|
| `$HOME/.local/bin/claude` | Path to the real Claude CLI binary (update if installed elsewhere) |

### Project Working Directory (`lucy/bin/new-claude`)
| Placeholder | Description |
|---|---|
| `~/Claude` | Default `cd` target when launching new Claude sessions |

### WSL2/Windows Paths (`config/tmux.conf`)
| Placeholder | Description |
|---|---|
| `/mnt/c/Windows/System32/clip.exe` | Windows clipboard binary (WSL2 only; remove or change for native Linux/macOS) |

### Notification Sound
| File | Description |
|---|---|
| `~/.claude/notify-sound.mp3` | Place any MP3 file here for desktop/browser notification audio |

---

## 3. Hook Configuration (`config/settings.json`)

### Session Naming Hook (`hooks/name-session.sh`)
| Placeholder | Description |
|---|---|
| `YOUR_ANTHROPIC_API_KEY` | API key for the Haiku call that generates session names (uses ~50 tokens per session) |

### Notification Hook (`hooks/notify-idle.sh`)
| Item | Description |
|---|---|
| `NOTIFY_URL` | Default: `http://localhost:9199/notify` (the notify-server.js endpoint) |
| PowerShell sound path | Path to notification sound on Windows side (for WSL2 desktop audio) |
| `CONTEXT_WARN_PCT` | Context usage % to start warning (default: 70) |

### Workspace Token Gate (`hooks/workspace-token-gate.sh`, `hooks/workspace-token-check.sh`)
| Item | Description |
|---|---|
| Token check script path | Points to `~/.claude/hooks/workspace-token-check.sh` |
| MCP server name | Must match your google-workspace MCP server name in settings |

### Disk Check Hook (`hooks/disk-check.sh`)
| Item | Description |
|---|---|
| Threshold | Default: 10GB minimum free space before blocking Bash tool |

---

## 4. Lucy Multi-Agent Configuration (`lucy/config.sh`)

### Model Mappings
The `MODEL_MAP` associative array maps friendly names to model IDs. Update if you use different models:
```bash
declare -A MODEL_MAP=(
  [sonnet]="claude-sonnet-4-6"
  [opus]="claude-opus-4-6"
  [haiku]="claude-haiku-4-5"
  # Add your own model aliases here
)
```

### Agent Binary Mappings
The `AGENT_BIN` array maps model names to CLI binaries. Update if using non-default agents:
```bash
declare -A AGENT_BIN=(
  [sonnet]="claude"
  [opus]="claude"
  [haiku]="claude"
  # Add entries for any custom agents
)
```

### Repo Group Mapping
Map repository names to groups for context siloing:
```bash
declare -A REPO_GROUP_MAP=(
  [MyProject]="myproject"
  [ClientRepo]="client"
)
```

### Concurrency & Resources
| Variable | Default | Description |
|---|---|---|
| `MAX_CONCURRENT` | `10` | Maximum simultaneous agents (env: `LUCY_MAX_CONCURRENT`) |
| `MIN_AVAIL_MEM_MB` | `4096` | Minimum free RAM before spawning (env: `LUCY_MIN_AVAIL_MEM_MB`) |
| `RATE_LIMIT_BONUS_RETRIES` | `5` | Extra retries for rate-limit errors (env: `LUCY_RATE_LIMIT_BONUS_RETRIES`) |
| `MAX_RETRIES` | `3` | Default max retries per task |

---

## 5. agent-browser Profiles

Create persistent browser profiles for each service that needs login sessions:
```bash
mkdir -p ~/.agent-browser/profiles/{service-name}
```
Then launch with:
```bash
agent-browser --session {service} --profile ~/.agent-browser/profiles/{service} --session-name {service} open {url}
```

---

## 6. Chrome Anti-Invalidation (`lucy/bin/chrome-start`)

The `chrome-start` script launches Chrome with flags that prevent session revocation. Review and update:
- The Chrome binary path (default assumes Windows Chrome via WSL2)
- The user data directory path
- The debug port (default: 9222)

---

## 7. Third-Party Tools

### gstack (Playwright-based browser)
Install separately:
```bash
# gstack is a third-party tool for headless browsing
# Install it according to its documentation, then place the binary at:
# ~/.claude/skills/gstack/browse/dist/browse
```

### agent-browser
```bash
npm install -g agent-browser
```

---

## File Placement

| Repo Path | Install To |
|---|---|
| `config/settings.json` | `~/.claude/settings.json` |
| `config/.mcp.json` | `~/Claude/.mcp.json` (project-level) or `~/.claude/.mcp.json` (global) |
| `config/tmux.conf` | `~/.tmux.conf` or source from existing config |
| `config/bashrc.example` | Append to `~/.bashrc` |
| `hooks/*` | `~/.claude/hooks/` (referenced by settings.json) |
| `lucy/` | `~/.claude/lucy/` |
| `scripts/notify-server.js` | `~/.claude/notify-server.js` |
| `scripts/win-idle.ps1` | `~/.claude/scripts/win-idle.ps1` |
| `scripts/win-play.ps1` | `~/.claude/scripts/win-play.ps1` |
| `scripts/snooze-resume.sh` | `~/.claude/scripts/snooze-resume.sh` |
| `skills/` | `~/.claude/skills/` |
| `CLAUDE.md.example` | `~/Claude/CLAUDE.md` (customize per project) |
| `crontab.example` | `crontab -e` (add relevant lines) |

## Dependencies

- **Node.js** (for notify-server.js)
- **jq** (JSON processing, used extensively by Lucy and hooks)
- **tmux** (session management)
- **Python 3** (Lucy orchestrator uses inline Python for task management)
- **curl** (notifications, API calls)
- **Claude CLI** (`claude`): Install from Anthropic
- **GitHub CLI** (`gh`): For PR creation/management
- **agent-browser**: `npm install -g agent-browser`
- **PowerShell** (WSL2 only, for Windows-side notifications)

## Verification

After setup, verify with:
```bash
# Check Lucy bin is on PATH
which lucy-status

# Check notification server
node ~/.claude/notify-server.js &
curl -s http://localhost:9199/debug | jq .

# Check agent-browser health
ab-doctor

# Check Chrome debug port
curl -s http://localhost:9222/json/version | jq .

# Run Lucy status dashboard
lucy-status
```

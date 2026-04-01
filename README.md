# Claude Code Toolkit

A comprehensive system for running Claude Code as an autonomous agent with multi-terminal management, browser automation, notification cascading, session persistence, and multi-agent orchestration.

Built for **WSL2 + Windows** environments with tmux, but most components are portable.

## What's Included

### Hooks (`hooks/`)
Claude Code hooks that fire on various lifecycle events:

| Hook | Event | Purpose |
|------|-------|---------|
| `name-session.sh` | UserPromptSubmit | Auto-names tmux sessions from first substantive prompt using Haiku |
| `compact-suggest.sh` | PreToolUse | Suggests `/compact` after N tool calls to prevent context overflow |
| `zapier-title-check.sh` | PreToolUse | Blocks Zapier zap creation without a title |
| `workspace-token-gate.sh` | PreToolUse | Blocks Google Workspace MCP calls when tokens are broken |
| `workspace-token-check.sh` | Cron | Checks Google Workspace token health hourly |
| `chrome-tab-track.sh` | PostToolUse | Tracks tabs opened via Chrome DevTools MCP per terminal |
| `chrome-tab-cleanup.sh` | Stop | Closes tabs owned by the exiting terminal |
| `chrome-mcp-cleanup.sh` | Stop | Kills orphaned chrome-devtools-mcp node processes |
| `agent-browser-cleanup.sh` | Stop | Closes agent-browser sessions owned by the exiting terminal |
| `notify-idle.sh` | Notification (idle) | Cascading audio notification: desktop, laptop, phone |
| `notify-stop-debounce.sh` | Stop | 20s debounced fallback notification |
| `session-save.sh` | Stop | Saves session summary to `~/.claude/sessions/YYYY-MM/` |
| `enforce-memory-promises.sh` | Stop | Catches "saved to memory" promises without real enforcement |
| `fix-last-prompt.sh` | Stop | Fixes `/resume` display to show original topic, not last prompt |
| `lucy-cleanup.sh` | Stop | Kills Lucy sub-agents spawned by the exiting terminal |
| `disk-check.sh` | PreToolUse (Bash) | Blocks tool use when disk space is critically low |

### Lucy Multi-Agent Orchestrator (`lucy/`)
A complete system for spawning, monitoring, and reviewing autonomous coding agents:

- **lucy-spawn**: Creates git worktrees, assembles prompts, launches agents in tmux
- **lucy-monitor**: Cron script that detects PRs, triggers reviews, auto-retries failures
- **lucy-assess**: Periodic one-shot orchestrator using Claude for intelligent assessment
- **lucy-review**: Adversarial code review using a separate model
- **lucy-verify**: Antagonistic verification of acceptance criteria
- **lucy-gate**: Deterministic quality gates (lint, typecheck, test)
- **lucy-kill/status/redirect**: Agent lifecycle management

### Browser Automation (`lucy/bin/`)
- **chrome-start**: Launch Chrome with anti-session-invalidation flags
- **chrome-tabs**: Tab lifecycle manager with per-terminal ownership tracking
- **chrome-session**: Isolated Chrome debug instances with cookie sharing
- **chrome-mcp-toggle**: Dynamically add/remove Chrome DevTools MCP
- **agent-browser**: Safe wrapper for agent-browser with session isolation and derivative sessions
- **agent-browser-state-save**: Cron script to persist agent-browser sessions against crashes

### Skills (`skills/`)
Claude Code skill definitions (SKILL.md files) for various domains:
- GTM JavaScript (ES5-compliant tag generation)
- Lucy orchestrator interface
- Marketing skills (ad creative, AI SEO, cold email, content strategy, product marketing context)

### Configuration (`config/`)
- `settings.json`: Claude Code settings with hook configuration
- `keybindings.json`: Custom keybindings
- `mcp-templates.json`: MCP server configuration templates
- `.mcp.json`: Project-level MCP configuration
- `tmux.conf`: tmux configuration for the setup

### Scripts (`scripts/`)
- `snooze-resume.sh`: Session snooze/resume with cron-based wake-up

## Setup

1. Copy hooks to `~/.claude/hooks/`
2. Copy lucy bin scripts to `~/.claude/lucy/bin/` and add to PATH
3. Update `config/settings.json` with your hook paths and merge into `~/.claude/settings.json`
4. Update `config/mcp-templates.json` with your credentials and paths
5. Set up cron jobs (see `crontab.example`)
6. Copy skills to `~/.claude/skills/`

### Prerequisites
- Claude Code CLI
- tmux
- jq, python3
- WSL2 (for Windows-specific features like Chrome automation)
- agent-browser (`npm install -g agent-browser`)
- PowerShell access via WSL (for Chrome management)

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Terminal 1  │     │  Terminal 2  │     │  Terminal N  │
│  (Claude)    │     │  (Claude)    │     │  (Claude)    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       ▼                    ▼                    ▼
┌──────────────────────────────────────────────────────────┐
│                    Hooks Layer                            │
│  UserPromptSubmit │ PreToolUse │ PostToolUse │ Stop      │
│  (name-session)   │ (compact)  │ (tab-track) │ (cleanup) │
└──────────────────────────────────────────────────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
┌──────────────────────────────────────────────────────────┐
│                  Shared Resources                        │
│  Chrome (port 9222) │ agent-browser profiles │ tmux     │
│  Tab ownership      │ Session state          │ Cron     │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                  Lucy Orchestrator                        │
│  lucy-spawn → worktree → agent → PR → gates → review   │
│  lucy-assess (periodic) → interventions → redirects     │
│  lucy-monitor (cron) → retry / escalate / verify        │
└──────────────────────────────────────────────────────────┘
```

## Customization

Most scripts use `$HOME` paths and are designed to be portable. You'll need to customize:

- Windows paths in `chrome-start`, `chrome-session` (if not on WSL2)
- Notification URLs in `lucy/config.sh`
- MCP server credentials in `config/mcp-templates.json`
- Business-specific context in `lucy/context/` (not included; create your own)

## License

Private. Not for redistribution.

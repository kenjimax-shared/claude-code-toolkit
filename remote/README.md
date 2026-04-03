# Remote Claude Code Setup

Run Claude Code on an always-on machine and access it from your phone and laptop through a web browser. Your phone is a mirror of your desktop: creating or killing a session on one shows up on the other within seconds.

## What's included

- **code-server** (VS Code in the browser) with tmux integration and keyboard shortcuts
- **tmux-mobile** PWA for managing sessions from your phone (touch gestures, swipe-to-accept)
- **code-server extension** that mirrors phone and desktop sessions automatically
- **Notification server** with browser audio and optional push notifications via ntfy.sh
- **Claude Code hooks** for auto-naming sessions, saving transcripts, and context management

## Architecture

```
+-----------------------------------------------------+
|  Machine (always on, WSL2 or Linux)                  |
|  +-----------------------------------------------+  |
|  |  tmux          code-server (:8080)             |  |
|  |  sessions  <-- VS Code in browser              |  |
|  |            <-- tmux-mobile (:3200) Phone PWA   |  |
|  |                                                |  |
|  |  notify-server (:9199) --> browser audio       |  |
|  |                        --> ntfy.sh (push)      |  |
|  +-----------------------------------------------+  |
|                                                      |
|  Tailscale VPN --> accessible at <tailscale-ip>      |
+------------------------------------------------------+
```

Phone and laptop sessions are mirrored: the code-server extension polls
`~/.claude/snooze-active/` and opens terminal tabs for new tmux sessions.
tmux-mobile writes markers there on create and removes them on kill.

## Prerequisites

- Linux or WSL2 (Ubuntu recommended)
- [Tailscale](https://tailscale.com/) on both the machine and your phone/laptop
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- Node.js 18+
- tmux

## Installation

### 1. Tailscale

Install Tailscale on your machine and on your phone/laptop. Note the machine's Tailscale IP (e.g., `100.x.y.z`).

### 2. code-server

```bash
curl -fsSL https://code-server.dev/install.sh | sh

mkdir -p ~/.config/code-server
cp remote/code-server/config.yaml ~/.config/code-server/config.yaml
# Edit config.yaml and set a strong password

sudo systemctl enable --now code-server@$USER
```

Copy keybindings and settings:

```bash
mkdir -p ~/.local/share/code-server/User
cp remote/code-server/keybindings.json ~/.local/share/code-server/User/
cp remote/code-server/settings.json ~/.local/share/code-server/User/
```

### 3. tmux

```bash
sudo apt install tmux
cp config/tmux.conf ~/.tmux.conf
```

### 4. code-server extension (session mirroring)

This extension auto-opens terminal tabs in code-server for tmux sessions. When you create a session on your phone, it appears in code-server within 5 seconds.

```bash
EXT_DIR="$HOME/.local/share/code-server/extensions/local.claude-snooze-1.0.0"
mkdir -p "$EXT_DIR"
cp remote/code-server-extension/extension.js "$EXT_DIR/"
cp remote/code-server-extension/package.json "$EXT_DIR/"
# Restart code-server to load the extension
sudo systemctl restart code-server@$USER
```

### 5. tmux-mobile (phone access)

```bash
cp -r remote/tmux-mobile ~/tmux-mobile
cd ~/tmux-mobile
npm install
npm run build

# Optional: set your working directory (defaults to ~/Claude)
# export CLAUDE_WORK_DIR=/path/to/your/project

# Install systemd service
mkdir -p ~/.config/systemd/user
cp tmux-mobile.service ~/.config/systemd/user/
systemctl --user enable --now tmux-mobile
```

On your phone, navigate to `http://<tailscale-ip>:3200` and "Add to Home Screen" to install the PWA.

### 6. Notification server (optional)

```bash
mkdir -p ~/.claude/hooks

# Copy the notification server
cp remote/notifications/notify-server.js ~/.claude/notify-server.js
cp remote/notifications/notify-stop.sh ~/.claude/hooks/notify-stop.sh
chmod +x ~/.claude/hooks/notify-stop.sh

# Place an MP3 file at ~/.claude/notify-sound.mp3

# Install systemd service
cp remote/notifications/claude-notify.service ~/.config/systemd/user/
systemctl --user enable --now claude-notify
```

For push notifications, set your ntfy.sh topic:

```bash
# In the service file or as an env var:
Environment=NTFY_TOPIC=your-random-topic-here
```

For Windows-side audio (plays through speakers when at the machine):

```powershell
Copy-Item remote/notifications/notify-local.ps1 ~\.claude\hooks\notify-local.ps1
```

### 7. Claude Code hooks

```bash
cp hooks/name-session.sh ~/.claude/hooks/
cp hooks/compact-suggest.sh ~/.claude/hooks/
cp hooks/session-save.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# Merge remote/claude-settings.json into your ~/.claude/settings.json
# or copy it if starting fresh:
cp remote/claude-settings.json ~/.claude/settings.json
```

### 8. Shell configuration

Add to your `~/.bashrc` (see `remote/shell/bashrc-additions.sh`):

```bash
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [ -n "$TERM_PROGRAM" ]; then
    tmux new-session -A -s main
fi
```

## Keyboard Shortcuts (code-server)

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+`` | Split terminal + start new Claude session in tmux |
| `Ctrl+Shift+1` | Split terminal + attach to existing tmux session |
| `Shift+Enter` | Send ESC+Enter (multi-line input in Claude) |

## Phone Gestures (tmux-mobile)

| Gesture | Action |
|---|---|
| **Swipe right** | Accept Claude suggestion (sends right arrow) |
| **Vertical swipe** | Scroll terminal output |
| **Tap link** | Open URL in new tab |
| **Long press** | Selectable text overlay (copy/paste) |
| **Hamburger menu** | Session drawer: switch, create, kill sessions |

## Customization

| Setting | How |
|---|---|
| **Ports** | `PORT` env var for tmux-mobile (default 3200), edit config.yaml for code-server (default 8080) |
| **Working directory** | `CLAUDE_WORK_DIR` env var for tmux-mobile, edit keybindings.json for code-server |
| **ntfy topic** | `NTFY_TOPIC` env var in the claude-notify service |
| **Compact threshold** | `ECC_COMPACT_THRESHOLD` env var (default 50 tool calls) |

## Security

- code-server is password-protected but runs plain HTTP. Tailscale provides encryption; do not expose ports to the public internet.
- The notification server has no authentication. Run on localhost/Tailscale only.
- ntfy.sh topics are public by default. Use a long random string or self-host.

## File Overview

```
remote/
  tmux-mobile/           Phone PWA (Express + WebSocket + xterm.js)
    server.js            Backend: tmux attach via PTY, session CRUD, notification proxy
    src/                 Frontend: terminal view, session list, input bar, styles
    public/              PWA shell: HTML, manifest, service worker, icon
    build.mjs            esbuild bundler
    package.json         Dependencies
    tmux-mobile.service  systemd user service

  code-server/           VS Code in the browser
    config.yaml          Bind address + auth
    keybindings.json     Ctrl+Shift+` and Ctrl+Shift+1 shortcuts
    settings.json        Dark theme, copy on selection

  code-server-extension/ Session mirroring extension
    extension.js         Polls ~/.claude/snooze-active/, opens terminal tabs
    package.json         Extension manifest

  notifications/         Notification server + hooks
    notify-server.js     HTTP server: poll endpoint, ntfy.sh push, image upload
    notify-stop.sh       Claude Stop hook: fires notifications
    notify-local.ps1     Windows audio playback (optional)
    claude-notify.service  systemd user service

  shell/
    bashrc-additions.sh  Auto-attach to tmux in code-server

  claude-settings.json   Example Claude Code hook configuration
```

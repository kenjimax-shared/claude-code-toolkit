import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import { spawn } from 'node-pty';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { createReadStream, statSync, writeFileSync, unlinkSync, mkdirSync, readdirSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = parseInt(process.env.PORT || '3200', 10);

// Working directory for new Claude sessions.
// Override with CLAUDE_WORK_DIR env var or defaults to ~/Claude.
const WORKING_DIR = process.env.CLAUDE_WORK_DIR || join(process.env.HOME, 'Claude');

// code-server extension (local.claude-snooze) polls this dir and opens terminal
// tabs for any file whose name matches a live tmux session
const SNOOZE_DIR = join(process.env.HOME, '.claude', 'snooze-active');
mkdirSync(SNOOZE_DIR, { recursive: true });

const app = express();
const server = http.createServer(app);

// Android App Links: let the PWA claim URLs from this origin
app.get('/.well-known/assetlinks.json', (_req, res) => {
  res.json([]);
});

// Serve static files: dist/ for bundled JS, public/ for HTML/manifest/sw
app.use(express.static(join(__dirname, 'public')));
app.use('/dist', express.static(join(__dirname, 'dist')));

// Persistent PTY map: sessionName -> { pty, ws }
// PTYs stay alive across WebSocket disconnects so phone viewing
// doesn't trigger tmux client-detach (which would fire destroy-unattached)
const activePTYs = new Map();

// Patterns for sessions that should be hidden from mobile
const HIDDEN_SESSION_PATTERNS = [
  /^lucy-/,          // Lucy orchestration sessions
];

function isHiddenSession(name) {
  return HIDDEN_SESSION_PATTERNS.some(p => p.test(name));
}

// Build a map of session -> whether Claude is running (not just a dead bash shell)
function getAliveMap() {
  try {
    const raw = execSync('tmux list-panes -a -F "#{session_name}|#{pane_current_command}"', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const map = new Map();
    for (const line of raw.trim().split('\n').filter(Boolean)) {
      const sep = line.indexOf('|');
      if (sep === -1) continue;
      const sess = line.substring(0, sep);
      const cmd = line.substring(sep + 1).trim();
      // If any pane runs something other than a bare shell, session is alive
      const isShell = ['bash', 'sh', 'zsh', 'fish', ''].includes(cmd);
      if (!isShell) map.set(sess, true);
      else if (!map.has(sess)) map.set(sess, false);
    }
    return map;
  } catch {
    return new Map();
  }
}

// REST: list tmux sessions (filtered: no Lucy sessions, includes alive status)
app.get('/api/sessions', (_req, res) => {
  try {
    const raw = execSync('tmux list-sessions -F "#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}"', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const aliveMap = getAliveMap();
    const sessions = raw.trim().split('\n').filter(Boolean).map(line => {
      const [name, windows, attached, activity] = line.split('|');
      return {
        name,
        windows: parseInt(windows, 10),
        attached: parseInt(attached, 10) > 0,
        lastActivity: parseInt(activity, 10),
        alive: aliveMap.get(name) || false,
      };
    }).filter(s => !isHiddenSession(s.name));
    res.json(sessions);
  } catch {
    res.json([]);
  }
});

// REST: create a new tmux session running claude --dangerously-skip-permissions
app.post('/api/sessions', (_req, res) => {
  try {
    execSync(`tmux new-session -d -c ${JSON.stringify(WORKING_DIR)} claude\\ --dangerously-skip-permissions`, {
      timeout: 5000,
      cwd: WORKING_DIR,
      env: { ...process.env, TERM: 'xterm-256color' },
    });
    // Get the name of the just-created session (most recent)
    const raw = execSync('tmux list-sessions -F "#{session_name}|#{session_activity}" | sort -t"|" -k2 -rn | head -1', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const name = raw.trim().split('|')[0];
    // Write marker so code-server extension opens a terminal tab for this session
    try { writeFileSync(join(SNOOZE_DIR, name), '', { flag: 'w' }); } catch {}
    res.json({ ok: true, name });
  } catch (err) {
    res.status(500).json({ error: 'failed to create session' });
  }
});

// REST: kill a tmux session
app.delete('/api/sessions/:name', (req, res) => {
  const name = req.params.name;
  // Kill persistent PTY first so it doesn't hold the session alive
  const entry = activePTYs.get(name);
  if (entry) {
    entry.pty.kill();
    activePTYs.delete(name);
  }
  // Remove snooze marker so code-server closes the terminal tab
  try { unlinkSync(join(SNOOZE_DIR, name)); } catch {}
  try {
    execSync(`tmux kill-session -t ${JSON.stringify(name)}`, { timeout: 3000 });
    res.json({ ok: true });
  } catch {
    res.status(500).json({ error: 'failed to kill session' });
  }
});

// Notification proxy: poll the notify server (port 9199)
app.get('/api/notify/poll', (req, res) => {
  const idle = req.query.idle || '0';
  const session = req.query.session || '';
  const proxyReq = http.get(`http://localhost:9199/poll?idle=${idle}&source=mobile&session=${encodeURIComponent(session)}`, {
    headers: { 'User-Agent': 'tmux-mobile' },
  }, (proxyRes) => {
    let data = '';
    proxyRes.on('data', chunk => data += chunk);
    proxyRes.on('end', () => {
      res.set('Content-Type', 'application/json');
      res.set('Cache-Control', 'no-store');
      res.send(data);
    });
  });
  proxyReq.on('error', () => res.json({ count: 0 }));
});

// Notification proxy: serve notification sound
app.get('/api/notify/sound', (_req, res) => {
  const soundPath = join(process.env.HOME, '.claude', 'notify-sound.mp3');
  try {
    const stat = statSync(soundPath);
    res.set('Content-Type', 'audio/mpeg');
    res.set('Content-Length', stat.size);
    res.set('Cache-Control', 'public, max-age=86400');
    createReadStream(soundPath).pipe(res);
  } catch {
    res.status(404).end();
  }
});

// WebSocket: terminal connections
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const match = url.pathname.match(/^\/ws\/terminal\/(.+)$/);
  if (!match) {
    socket.destroy();
    return;
  }
  const sessionName = decodeURIComponent(match[1]);
  wss.handleUpgrade(req, socket, head, ws => {
    wss.emit('connection', ws, req, sessionName);
  });
});

wss.on('connection', (ws, _req, sessionName) => {
  console.log(`[ws] connecting to tmux session: ${sessionName}`);

  let entry = activePTYs.get(sessionName);

  if (entry) {
    // Reuse existing PTY (phone reconnected after screen dim, etc.)
    console.log(`[ws] reusing existing PTY for session: ${sessionName}`);
    // Close old WS if still lingering
    if (entry.ws && entry.ws !== ws && entry.ws.readyState === 1) {
      entry.ws.onclose = null;
      entry.ws.onerror = null;
      entry.ws.close();
    }
    entry.ws = ws;
  } else {
    // Spawn new PTY
    console.log(`[ws] spawning new PTY for session: ${sessionName}`);
    const pty = spawn('tmux', ['attach-session', '-t', sessionName], {
      name: 'xterm-256color',
      cols: 52,
      rows: 30,
      cwd: process.env.HOME,
      env: { ...process.env, TERM: 'xterm-256color' },
    });

    entry = { pty, ws };
    activePTYs.set(sessionName, entry);

    // PTY -> current WS (closure reads entry.ws so it always routes to latest)
    pty.onData(data => {
      if (entry.ws && entry.ws.readyState === 1) {
        entry.ws.send(data, { binary: false });
      }
    });

    pty.onExit(({ exitCode }) => {
      console.log(`[ws] pty exited (code ${exitCode}) for session: ${sessionName}`);
      activePTYs.delete(sessionName);
      if (entry.ws && entry.ws.readyState === 1) {
        entry.ws.close(1000, 'pty exited');
      }
    });
  }

  // WS -> PTY
  ws.on('message', (msg) => {
    if (entry.ws !== ws) return; // stale WS, ignore
    try {
      const parsed = JSON.parse(msg.toString());
      if (parsed.type === 'resize' && parsed.cols && parsed.rows) {
        entry.pty.resize(parsed.cols, parsed.rows);
        return;
      }
      if (parsed.type === 'input' && typeof parsed.data === 'string') {
        entry.pty.write(parsed.data);
        return;
      }
    } catch {
      // Not JSON: treat as raw input
      entry.pty.write(msg.toString());
    }
  });

  // WS disconnect: keep PTY alive so reconnects (screen dim, network blip) are seamless
  ws.on('close', () => {
    console.log(`[ws] client disconnected from session: ${sessionName}`);
    if (entry.ws === ws) {
      entry.ws = null;
    }
  });

  ws.on('error', (err) => {
    console.error(`[ws] error for session ${sessionName}:`, err.message);
    if (entry.ws === ws) {
      entry.ws = null;
    }
  });
});

// Detect session renames by matching PTY PIDs to tmux client PIDs
setInterval(() => {
  if (activePTYs.size === 0) return;
  try {
    const raw = execSync('tmux list-clients -F "#{client_pid} #{session_name}"', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const pidToSession = new Map();
    for (const line of raw.trim().split('\n').filter(Boolean)) {
      const spaceIdx = line.indexOf(' ');
      if (spaceIdx === -1) continue;
      const pid = parseInt(line.substring(0, spaceIdx), 10);
      const sessName = line.substring(spaceIdx + 1);
      if (!isNaN(pid)) pidToSession.set(pid, sessName);
    }
    for (const [name, entry] of activePTYs) {
      const newName = pidToSession.get(entry.pty.pid);
      if (newName && newName !== name) {
        console.log(`[rename] session renamed: ${name} -> ${newName}`);
        activePTYs.delete(name);
        activePTYs.set(newName, entry);
        if (entry.ws && entry.ws.readyState === 1) {
          entry.ws.send(JSON.stringify({ type: 'sessionRenamed', name: newName }));
        }
      }
    }
  } catch {}
}, 3000);

// Periodic cleanup: remove PTYs for tmux sessions that no longer exist
setInterval(() => {
  if (activePTYs.size === 0) return;
  try {
    const raw = execSync('tmux list-sessions -F "#{session_name}"', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const liveSessions = new Set(raw.trim().split('\n').filter(Boolean));
    for (const [name, entry] of activePTYs) {
      if (!liveSessions.has(name)) {
        // Check if PTY process is still alive (session may have been renamed
        // but the 3s rename check hasn't caught it yet)
        let alive = false;
        try { process.kill(entry.pty.pid, 0); alive = true; } catch {}
        if (alive) continue;

        console.log(`[cleanup] removing orphaned PTY for: ${name}`);
        entry.pty.kill();
        if (entry.ws && entry.ws.readyState === 1) {
          entry.ws.close(1000, 'session gone');
        }
        activePTYs.delete(name);
      }
    }
  } catch {
    // tmux not running at all, clear everything
    for (const [, entry] of activePTYs) {
      entry.pty.kill();
    }
    activePTYs.clear();
  }
}, 30000);

// Auto-cleanup: kill tmux sessions where Claude is no longer running
// Runs every 2 minutes. Only kills sessions that:
// 1. Have no Claude process (only a bare shell)
// 2. Have no snooze-active marker (not awaiting scheduled resume)
// 3. Have been idle for > 5 minutes
// 4. Are not hidden (Lucy) sessions — those are managed separately
const IDLE_THRESHOLD_SEC = 300; // 5 minutes
setInterval(() => {
  try {
    const aliveMap = getAliveMap();
    const markers = new Set();
    try { for (const f of readdirSync(SNOOZE_DIR)) markers.add(f); } catch {}

    const raw = execSync('tmux list-sessions -F "#{session_name}|#{session_attached}|#{session_activity}"', {
      encoding: 'utf8',
      timeout: 3000,
    });
    const now = Math.floor(Date.now() / 1000);
    for (const line of raw.trim().split('\n').filter(Boolean)) {
      const [name, attached, activity] = line.split('|');
      const idle = now - parseInt(activity, 10);
      const isAttached = parseInt(attached, 10) > 0;

      // Skip if alive (Claude is running)
      if (aliveMap.get(name)) continue;
      // Skip if attached from code-server (user may still be looking at it)
      if (isAttached) continue;
      // Skip if has snooze marker (scheduled for resume)
      if (markers.has(name)) continue;
      // Skip if hidden (Lucy) — managed by Lucy orchestrator
      if (isHiddenSession(name)) continue;
      // Skip if not idle long enough
      if (idle < IDLE_THRESHOLD_SEC) continue;

      console.log(`[auto-cleanup] killing dead session: ${name} (idle ${idle}s, no claude process)`);
      // Clean up PTY if we have one
      const entry = activePTYs.get(name);
      if (entry) {
        entry.pty.kill();
        activePTYs.delete(name);
      }
      try { unlinkSync(join(SNOOZE_DIR, name)); } catch {}
      try { execSync(`tmux kill-session -t ${JSON.stringify(name)}`, { timeout: 3000 }); } catch {}
    }
  } catch {}
}, 120000); // Every 2 minutes

let bindAttempts = 0;
const MAX_PORT_ATTEMPTS = 10;
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE' && bindAttempts < MAX_PORT_ATTEMPTS) {
    bindAttempts++;
    const fallback = PORT + bindAttempts;
    console.warn(`[startup] port ${PORT + bindAttempts - 1} in use, trying ${fallback}...`);
    server.listen(fallback, '0.0.0.0');
  } else {
    throw err;
  }
});

server.listen(PORT, '0.0.0.0', () => {
  const addr = server.address();
  console.log(`tmux-mobile listening on http://0.0.0.0:${addr.port}`);
});

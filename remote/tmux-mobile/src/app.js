import '@xterm/xterm/css/xterm.css';
import './styles.css';
import { TerminalView } from './terminal-view.js';
import { SessionList } from './session-list.js';
// DOM refs
const menuBtn = document.getElementById('menu-btn');
const sessionNameEl = document.getElementById('session-name');
const statusDot = document.getElementById('status-dot');
const termContainer = document.getElementById('terminal');
const drawerOverlay = document.getElementById('drawer-overlay');
const drawer = document.getElementById('drawer');
const sessionListEl = document.getElementById('session-list');
const refreshBtn = document.getElementById('refresh-btn');

// Components
const termView = new TerminalView(termContainer);
const sessionList = new SessionList(drawer, drawerOverlay, sessionListEl, refreshBtn);

// State
let currentSession = null;
let reconnectTimer = null;

function setConnected(connected) {
  statusDot.classList.toggle('connected', connected);
}

function connectToSession(name) {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  currentSession = name;
  sessionNameEl.textContent = name;
  sessionList.activeSession = name;

  termView.onConnect = () => setConnected(true);
  termView.onDisconnect = () => {
    setConnected(false);
    // Auto-reconnect after 2s (use currentSession, not closure var, in case of rename)
    if (currentSession) {
      reconnectTimer = setTimeout(() => {
        if (currentSession) {
          termView.connect(currentSession);
        }
      }, 2000);
    }
  };
  termView.onRename = (newName) => {
    currentSession = newName;
    sessionNameEl.textContent = newName;
    sessionList.activeSession = newName;
  };

  termView.connect(name);
}

// Fullscreen: auto-enter on first touch, button to toggle
function enterFullscreen() {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen().catch(() => {});
  }
}

const fullscreenBtn = document.getElementById('fullscreen-btn');
fullscreenBtn.addEventListener('click', () => {
  if (document.fullscreenElement) {
    document.exitFullscreen();
  } else {
    enterFullscreen();
  }
});

// Auto-fullscreen on first user interaction
document.addEventListener('click', function autoFS() {
  enterFullscreen();
  document.removeEventListener('click', autoFS);
}, { once: true });
document.addEventListener('touchstart', function autoFS() {
  enterFullscreen();
  document.removeEventListener('touchstart', autoFS);
}, { once: true });

// Wiring
menuBtn.addEventListener('click', () => sessionList.toggle());

sessionList.onSelect = (name) => {
  connectToSession(name);
};

sessionList.onKill = (name) => {
  // If we killed the active session, connect to another one
  if (currentSession === name) {
    termView.disconnect();
    setConnected(false);
    currentSession = null;
    sessionNameEl.textContent = '(disconnected)';
    // Try connecting to first remaining session
    const remaining = sessionList.sessions.filter(s => s.name !== name);
    if (remaining.length > 0) {
      connectToSession(remaining[0].name);
    }
  }
};

// Virtual keyboard handling: resize app to fit above keyboard and scroll to bottom
const appEl = document.getElementById('app');
if (window.visualViewport) {
  window.visualViewport.addEventListener('resize', () => {
    const vvHeight = window.visualViewport.height;
    const vvOffsetTop = window.visualViewport.offsetTop;
    appEl.style.height = `${vvHeight}px`;
    appEl.style.transform = `translateY(${vvOffsetTop}px)`;
    termView.scrollToBottom();
  });
}

// Visibility change: reconnect when phone wakes up
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && currentSession) {
    // Small delay to let network recover
    setTimeout(() => {
      if (termView.ws && termView.ws.readyState !== WebSocket.OPEN) {
        termView.connect(currentSession);
      }
    }, 500);
  }
});

// Auto-connect to first session on load
async function init() {
  try {
    const res = await fetch('/api/sessions');
    const sessions = await res.json();
    if (sessions.length > 0) {
      connectToSession(sessions[0].name);
    } else {
      sessionNameEl.textContent = '(no sessions)';
    }
  } catch {
    sessionNameEl.textContent = '(offline)';
  }
}

init();

// --- Notification system ---
let audioCtx = null;
let notifySoundBuffer = null;
let lastNotifyCount = -1;
let lastActivity = Date.now();

// Track user activity for idle reporting
function resetActivity() { lastActivity = Date.now(); }
document.addEventListener('touchstart', resetActivity, { passive: true });
document.addEventListener('keydown', resetActivity);

// Unlock audio on first user gesture (mobile requires this)
async function unlockAudio() {
  if (audioCtx) return;
  try {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    // Play silent buffer to unlock audio output
    const buf = audioCtx.createBuffer(1, 1, 22050);
    const src = audioCtx.createBufferSource();
    src.buffer = buf;
    src.connect(audioCtx.destination);
    src.start(0);
    // Pre-load notification sound
    const res = await fetch('/api/notify/sound');
    const ab = await res.arrayBuffer();
    notifySoundBuffer = await audioCtx.decodeAudioData(ab);
  } catch {}
}
document.addEventListener('touchstart', unlockAudio, { once: true });
document.addEventListener('click', unlockAudio, { once: true });

function playNotifySound() {
  if (!audioCtx || !notifySoundBuffer) return;
  if (audioCtx.state === 'suspended') audioCtx.resume();
  const src = audioCtx.createBufferSource();
  src.buffer = notifySoundBuffer;
  src.connect(audioCtx.destination);
  src.start(0);
  if (navigator.vibrate) navigator.vibrate(200);
}

// Poll for notifications every 1.5s
setInterval(async () => {
  try {
    const idle = Math.floor((Date.now() - lastActivity) / 1000);
    const res = await fetch(`/api/notify/poll?idle=${idle}`);
    const data = await res.json();
    if (lastNotifyCount === -1) {
      lastNotifyCount = data.count;
      return;
    }
    if (data.count > lastNotifyCount) {
      lastNotifyCount = data.count;
      playNotifySound();
    }
  } catch {}
}, 1500);
